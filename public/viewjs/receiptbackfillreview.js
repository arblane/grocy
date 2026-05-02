var receiptReviewState = {
	staging: null,
	filteredRows: [],
	lastServerSummary: null
};

var receiptPdfAutoClearTimer = null;
var receiptJsonAutoClearTimer = null;

function EscapeHtml(value)
{
	return $('<div>').text(value == null ? '' : String(value)).html();
}

function StatusBadgeClass(status)
{
	switch (status)
	{
		case 'READY':
			return 'badge-success';
		case 'NO_STOCK_ENTRY':
			return 'badge-warning';
		case 'AMBIGUOUS_PRODUCT':
		case 'AMBIGUOUS_STOCK_ENTRY':
			return 'badge-danger';
		default:
			return 'badge-secondary';
	}
}

function GetEditableRows()
{
	if (!receiptReviewState.staging || !Array.isArray(receiptReviewState.staging.rows))
	{
		return [];
	}

	return receiptReviewState.staging.rows;
}

function EnsureCandidateProducts(row)
{
	function NormalizeCandidate(candidate)
	{
		if (!candidate)
		{
			return null;
		}

		var id = candidate.id;
		if (id == null && candidate.product_id != null)
		{
			id = candidate.product_id;
		}
		if (id == null || Number.isNaN(parseInt(id, 10)))
		{
			return null;
		}

		return {
			id: parseInt(id, 10),
			name: candidate.name || candidate.product_name || null,
			additional_details: candidate.additional_details || candidate.product_additional_details || null,
			strength: candidate.strength || null,
			size: candidate.size || null,
			package_configuration: candidate.package_configuration || null,
			brand: candidate.brand || null,
			display_name: candidate.display_name || null,
			score: candidate.score != null ? candidate.score : null
		};
	}

	if (Array.isArray(row.candidate_products) && row.candidate_products.length > 0)
	{
		return row.candidate_products.map(NormalizeCandidate).filter(function(candidate)
		{
			return candidate !== null;
		});
	}

	if (!Array.isArray(row.candidate_product_ids))
	{
		return [];
	}

	return row.candidate_product_ids.map(function(id)
	{
		return {
			id: parseInt(id, 10),
			name: null,
			additional_details: null,
			strength: null,
			size: null,
			package_configuration: null,
			brand: null,
			display_name: null,
			score: null
		};
	});
}

function ComposeCandidateProductDisplayName(candidate)
{
	if (candidate.display_name)
	{
		return candidate.display_name;
	}

	var parts = [];
	if (candidate.name)
	{
		parts.push(candidate.name);
	}
	if (candidate.additional_details)
	{
		parts.push(candidate.additional_details);
	}
	if (candidate.strength)
	{
		parts.push(candidate.strength);
	}
	if (candidate.size)
	{
		parts.push(candidate.size);
	}
	if (candidate.package_configuration)
	{
		parts.push(candidate.package_configuration);
	}

	var display = parts.join(', ');
	if (candidate.brand)
	{
		display += (display ? ' - ' : '') + candidate.brand;
	}

	if (display)
	{
		return display;
	}

	return __t('Product name unavailable');
}

function FormatPurchasedDateTime24h(rawValue)
{
	if (!rawValue)
	{
		return null;
	}

	var text = String(rawValue).trim();
	if (text === '')
	{
		return null;
	}

	// Handles common DB formats like "YYYY-MM-DD HH:MM:SS" and ISO variants.
	var match = text.match(/^(\d{4}-\d{2}-\d{2})[ T](\d{2}:\d{2})(?::\d{2})?/);
	if (match)
	{
		return match[1] + ' ' + match[2];
	}

	if (/^\d{4}-\d{2}-\d{2}$/.test(text))
	{
		return text;
	}

	return text;
}

function GetSelectedStockEntryCandidate(row, candidateStockEntries)
{
	if (!row || !Array.isArray(candidateStockEntries))
	{
		return null;
	}

	var selectedId = row.selected_stock_entry_id == null ? null : String(row.selected_stock_entry_id);
	if (!selectedId)
	{
		return null;
	}

	return candidateStockEntries.find(function(candidate)
	{
		return String(candidate.stock_id) === selectedId;
	}) || null;
}

function GetSelectedProductCandidate(row, candidateProducts)
{
	if (!row || !Array.isArray(candidateProducts))
	{
		return null;
	}

	var selectedId = row.selected_product_id == null ? null : String(row.selected_product_id);
	if (!selectedId)
	{
		return null;
	}

	return candidateProducts.find(function(candidate)
	{
		return String(candidate.id) === selectedId;
	}) || null;
}

function BuildSelectedProductMetaHtml(selectedProductCandidate)
{
	if (!selectedProductCandidate)
	{
		return '';
	}

	var fields = [
		{ label: __t('Additional details'), value: selectedProductCandidate.additional_details },
		{ label: __t('Size'), value: selectedProductCandidate.size },
		{ label: __t('Config'), value: selectedProductCandidate.package_configuration },
		{ label: __t('Brand'), value: selectedProductCandidate.brand }
	];

	var parts = fields.filter(function(field)
	{
		return field.value != null && String(field.value).trim() !== '';
	}).map(function(field)
	{
		return '<div class="small mt-1"><span class="text-muted">' + EscapeHtml(field.label) + ':</span> ' + EscapeHtml(String(field.value)) + '</div>';
	});

	return parts.join('');
}

function NeedsCandidateNameHydration(rows)
{
	if (!Array.isArray(rows) || rows.length === 0)
	{
		return false;
	}

	return rows.some(function(row)
	{
		var hasIds = Array.isArray(row.candidate_product_ids) && row.candidate_product_ids.length > 0;
		var normalizedCandidates = EnsureCandidateProducts(row);
		var hasAnyNamed = normalizedCandidates.some(function(candidate)
		{
			return !!candidate.name;
		});
		return hasIds && !hasAnyNamed;
	});
}

function EnsureCandidateStockEntries(row)
{
	if (Array.isArray(row.candidate_stock_entries) && row.candidate_stock_entries.length > 0)
	{
		return row.candidate_stock_entries;
	}

	if (!Array.isArray(row.candidate_stock_entry_ids))
	{
		return [];
	}

	return row.candidate_stock_entry_ids.map(function(stockId)
	{
		return {
			stock_id: stockId,
			amount: null,
			price: null,
			shopping_location_id: null,
			purchased_date: null
		};
	});
}

function BuildProductOverrideSelect(row)
{
	var candidates = EnsureCandidateProducts(row);
	var currentValue = row.manual_product_override_id == null ? '' : String(row.manual_product_override_id);
	var options = ['<option value="">' + EscapeHtml(__t('Auto')) + '</option>'];

	candidates.forEach(function(candidate)
	{
		var value = String(candidate.id);
		var label = ComposeCandidateProductDisplayName(candidate);
		var detailParts = [];
		if (candidate.stock_entries_in_window != null)
		{
			detailParts.push(__t('window stock') + ': ' + candidate.stock_entries_in_window);
		}
		if (candidate.latest_purchased_date)
		{
			detailParts.push(__t('latest') + ': ' + candidate.latest_purchased_date);
		}
		if (candidate.latest_price != null)
		{
			detailParts.push(__t('latest price') + ': $' + candidate.latest_price);
		}
		if (detailParts.length > 0)
		{
			label += ' | ' + detailParts.join(' | ');
		}
		options.push('<option value="' + EscapeHtml(value) + '" ' + (value === currentValue ? 'selected' : '') + '>' + EscapeHtml(label) + '</option>');
	});

	if (currentValue && candidates.findIndex(function(candidate)
	{
		return String(candidate.id) === currentValue;
	}) === -1)
	{
		options.push('<option value="' + EscapeHtml(currentValue) + '" selected>' + EscapeHtml(__t('Custom product override') + ' | ' + __t('ID') + ': ' + currentValue) + '</option>');
	}

	return '<select class="form-control form-control-sm manual-product-override-select">' + options.join('') + '</select>';
}

function BuildStockEntryOverrideSelect(row)
{
	var candidates = EnsureCandidateStockEntries(row);
	var currentValue = row.manual_stock_entry_override_id == null ? '' : String(row.manual_stock_entry_override_id);
	var options = ['<option value="">' + EscapeHtml(__t('Auto')) + '</option>'];

	candidates.forEach(function(candidate)
	{
		var value = String(candidate.stock_id);
		var purchasedDateTime = FormatPurchasedDateTime24h(candidate.purchased_date);
		var label = purchasedDateTime
			? (__t('Purchased') + ': ' + purchasedDateTime)
			: __t('Purchased date unavailable');
		var detailParts = [];
		if (candidate.price != null)
		{
			detailParts.push(__t('price') + ': $' + candidate.price);
		}
		if (candidate.shopping_location_id != null)
		{
			detailParts.push(__t('store') + ': ' + candidate.shopping_location_id);
		}
		if (detailParts.length > 0)
		{
			label += ' | ' + detailParts.join(' | ');
		}
		options.push('<option value="' + EscapeHtml(value) + '" ' + (value === currentValue ? 'selected' : '') + '>' + EscapeHtml(label) + '</option>');
	});

	if (currentValue && candidates.findIndex(function(candidate)
	{
		return String(candidate.stock_id) === currentValue;
	}) === -1)
	{
		options.push('<option value="' + EscapeHtml(currentValue) + '" selected>' + EscapeHtml(__t('Custom stock entry override') + ' (' + __t('not in current candidates') + ')') + '</option>');
	}

	return '<select class="form-control form-control-sm manual-stock-entry-override-select">' + options.join('') + '</select>';
}

function GetStatusCounts(rows)
{
	var counts = {};
	rows.forEach(function(row)
	{
		counts[row.status] = (counts[row.status] || 0) + 1;
	});
	return counts;
}

function SetActionButtonsEnabled(enabled)
{
	$('#download-staging-json-button, #copy-staging-json-button, #review-on-server-button, #apply-on-server-button').prop('disabled', !enabled);
}

function UpdateSummary()
{
	var rows = GetEditableRows();
	if (rows.length === 0)
	{
		$('#summary-store').text(__t('No staging JSON loaded')).addClass('text-muted');
		$('#summary-date').text('-');
		$('#summary-rows').text('0');
		$('#summary-ready').text('0');
		$('#summary-statuses').text('-');
		SetActionButtonsEnabled(false);
		return;
	}

	var counts = receiptReviewState.lastServerSummary && receiptReviewState.lastServerSummary.status_counts
		? receiptReviewState.lastServerSummary.status_counts
		: GetStatusCounts(rows);
	var readyCount = 0;
	rows.forEach(function(row)
	{
		if (row.status === 'READY')
		{
			readyCount += 1;
		}
	});

	$('#summary-store').text(receiptReviewState.staging.store_text || '-').removeClass('text-muted');
	$('#summary-date').text(receiptReviewState.staging.receipt_date || '-');
	$('#summary-rows').text(String(rows.length));
	$('#summary-ready').text(String(readyCount));
	$('#summary-statuses').text(Object.keys(counts).sort().map(function(key)
	{
		return key + ': ' + counts[key];
	}).join(', '));
	SetActionButtonsEnabled(true);
}

function RenderRows()
{
	var rows = GetEditableRows();
	var search = ($('#receipt-review-search').val() || '').trim().toLowerCase();
	var filteredRows = rows.filter(function(row)
	{
		if (!search)
		{
			return true;
		}

		return (row.parsed_description || '').toLowerCase().includes(search)
			|| (row.status || '').toLowerCase().includes(search)
			|| String(row.line_number || '').includes(search);
	});
	receiptReviewState.filteredRows = filteredRows;

	if (filteredRows.length === 0)
	{
		$('#receipt-review-table-body').html('<tr><td colspan="9" class="text-muted">' + EscapeHtml(__t('No rows match the current filter.')) + '</td></tr>');
		return;
	}

	var html = filteredRows.map(function(row)
	{
		if (row.status !== 'READY')
		{
			row.apply_selected = false;
		}

		var candidateProducts = EnsureCandidateProducts(row);
		var candidateStockEntries = EnsureCandidateStockEntries(row);
			var selectedProductCandidate = GetSelectedProductCandidate(row, candidateProducts);
			var selectedProductMetaHtml = BuildSelectedProductMetaHtml(selectedProductCandidate);
		var selectedStockEntryCandidate = GetSelectedStockEntryCandidate(row, candidateStockEntries);
		var selectedPurchasedDateTime = FormatPurchasedDateTime24h(selectedStockEntryCandidate ? selectedStockEntryCandidate.purchased_date : null);
		var selectedStockEntryText = selectedPurchasedDateTime
			? (__t('Purchased') + ': ' + selectedPurchasedDateTime)
			: '-';
		var selectedStockEntryMetaParts = [];
		if (row.current_stock_entry_amount != null && String(row.current_stock_entry_amount) !== '')
		{
			selectedStockEntryMetaParts.push(__t('amount') + ': ' + row.current_stock_entry_amount);
		}
		if (row.current_stock_entry_price != null && String(row.current_stock_entry_price) !== '')
		{
			selectedStockEntryMetaParts.push(__t('price') + ': $' + row.current_stock_entry_price);
		}
		if (selectedStockEntryCandidate && selectedStockEntryCandidate.shopping_location_id != null)
		{
			selectedStockEntryMetaParts.push(__t('store') + ': ' + selectedStockEntryCandidate.shopping_location_id);
		}
		var selectedStockEntryMeta = selectedStockEntryMetaParts.length > 0
			? selectedStockEntryMetaParts.join(' | ')
			: '';
		var parsedTotalValue = row.parsed_total_price != null && String(row.parsed_total_price).trim() !== ''
			? String(row.parsed_total_price).trim()
			: null;
		var proposedPriceValue = row.proposed_price != null && String(row.proposed_price).trim() !== ''
			? String(row.proposed_price).trim()
			: null;
		var currentPriceValue = row.current_stock_entry_price != null && String(row.current_stock_entry_price).trim() !== ''
			? String(row.current_stock_entry_price).trim()
			: null;
		var priceCheckParts = [];
		if (parsedTotalValue)
		{
			priceCheckParts.push('<div><span class="small text-muted">' + EscapeHtml(__t('Parsed total')) + ':</span> <strong>$' + EscapeHtml(parsedTotalValue) + '</strong></div>');
		}
		if (row.current_stock_entry_amount != null && String(row.current_stock_entry_amount) !== '')
		{
			priceCheckParts.push('<div><span class="small text-muted">' + EscapeHtml(__t('Matched stock amount')) + ':</span> <strong>' + EscapeHtml(String(row.current_stock_entry_amount)) + '</strong></div>');
		}
		if (proposedPriceValue)
		{
			priceCheckParts.push('<div><span class="small text-muted">' + EscapeHtml(__t('Proposed per-unit price')) + ':</span> <strong>$' + EscapeHtml(proposedPriceValue) + '</strong></div>');
		}

		if (proposedPriceValue)
		{
			if (currentPriceValue)
			{
				if (currentPriceValue === proposedPriceValue)
				{
					priceCheckParts.push('<div class="small text-success mt-1">' + EscapeHtml(__t('No change to existing price')) + '</div>');
				}
				else
				{
					priceCheckParts.push('<div class="small text-warning mt-1"><strong>' + EscapeHtml(__t('Will override existing price')) + '</strong>: $' + EscapeHtml(currentPriceValue) + ' -> $' + EscapeHtml(proposedPriceValue) + '</div>');
				}
			}
			else
			{
				priceCheckParts.push('<div class="small text-muted mt-1">' + EscapeHtml(__t('Will set price on empty stock entry')) + '</div>');
			}
		}
		else
		{
			priceCheckParts.push('<div class="small text-muted">' + EscapeHtml(__t('No proposed price')) + '</div>');
		}

		var priceCheckHtml = priceCheckParts.join('');
		var statusReason = row.status_reason ? '<div class="text-muted small mt-1">' + EscapeHtml(row.status_reason) + '</div>' : '';
		var productOverrideNotice = row.product_override_applied ? '<div class="small text-success mt-1">' + EscapeHtml(__t('Override applied')) + '</div>' : '';
		var stockOverrideNotice = row.stock_entry_override_applied ? '<div class="small text-success mt-1">' + EscapeHtml(__t('Override applied')) + '</div>' : '';
		var productOverrideHint = '';
		if (candidateProducts.length === 0)
		{
			productOverrideHint = '<div class="small text-muted mt-1">' + EscapeHtml(__t('No eligible product candidates (parent products are excluded).')) + '</div>';
		}
		else
		{
			productOverrideHint = '<div class="small text-muted mt-1">' + EscapeHtml(__t('%s eligible candidate(s) in dropdown', candidateProducts.length)) + '</div>';
		}

		if (Array.isArray(row.candidate_product_ids) && row.candidate_product_ids.length > 0 && candidateProducts.length === 0)
		{
			productOverrideHint += '<div class="small text-warning mt-1">' + EscapeHtml(__t('Click "Re-evaluate on server" to refresh candidates from current products.')) + '</div>';
		}

		if (candidateStockEntries.length === 0)
		{
			stockOverrideNotice += '<div class="small text-muted mt-1">' + EscapeHtml(__t('No stock-entry candidates')) + '</div>';
		}

		return ''
			+ '<tr data-line-number="' + EscapeHtml(row.line_number) + '">'
			+ '<td>' + EscapeHtml(row.line_number) + '</td>'
			+ '<td><strong>' + EscapeHtml(row.parsed_description) + '</strong><div class="small text-muted mt-1">' + EscapeHtml(row.parsed_quantity || '') + '</div></td>'
			+ '<td><span class="badge receipt-review-badge ' + StatusBadgeClass(row.status) + '">' + EscapeHtml(row.status || '') + '</span>' + statusReason + '</td>'
			+ '<td>' + BuildProductOverrideSelect(row) + productOverrideNotice + productOverrideHint + '</td>'
					+ '<td><div>' + EscapeHtml(row.selected_product_name || '-') + '</div><div class="small text-muted mt-1">' + EscapeHtml(row.selected_product_id || '') + '</div>' + selectedProductMetaHtml + '</td>'
			+ '<td>' + BuildStockEntryOverrideSelect(row) + stockOverrideNotice + '</td>'
			+ '<td><div>' + EscapeHtml(selectedStockEntryText) + '</div><div class="small text-muted mt-1">' + EscapeHtml(selectedStockEntryMeta) + '</div></td>'
			+ '<td>' + priceCheckHtml + '</td>'
			+ '<td><div class="form-check custom-control custom-checkbox"><input class="form-check-input custom-control-input apply-selected-input" type="checkbox" id="apply-selected-' + EscapeHtml(row.line_number) + '" ' + (row.apply_selected ? 'checked' : '') + ' ' + (row.status === 'READY' ? '' : 'disabled') + '><label class="form-check-label custom-control-label" for="apply-selected-' + EscapeHtml(row.line_number) + '"></label></div></td>'
			+ '</tr>';
	}).join('');

	$('#receipt-review-table-body').html(html);
}

function ResetReceiptPdfInput()
{
	if (receiptPdfAutoClearTimer)
	{
		clearTimeout(receiptPdfAutoClearTimer);
		receiptPdfAutoClearTimer = null;
	}

	var fileInput = $('#receipt-pdf-file');
	if (fileInput.length > 0)
	{
		fileInput.val('');
	}
}

function ResetStagingJsonInputs()
{
	if (receiptJsonAutoClearTimer)
	{
		clearTimeout(receiptJsonAutoClearTimer);
		receiptJsonAutoClearTimer = null;
	}

	$('#staging-json-file').val('');
	$('#staging-json-input').val('');
}

function ScheduleStagingJsonInputAutoClear()
{
	if (receiptJsonAutoClearTimer)
	{
		clearTimeout(receiptJsonAutoClearTimer);
	}

	// Clear raw JSON input after 10 minutes if it has not been loaded yet.
	receiptJsonAutoClearTimer = setTimeout(function()
	{
		ResetStagingJsonInputs();
	}, 10 * 60 * 1000);
}

function ScheduleReceiptPdfInputAutoClear()
{
	if (receiptPdfAutoClearTimer)
	{
		clearTimeout(receiptPdfAutoClearTimer);
	}

	// Clear selected PDF after 10 minutes if parsing has not been triggered.
	receiptPdfAutoClearTimer = setTimeout(function()
	{
		ResetReceiptPdfInput();
	}, 10 * 60 * 1000);
}

function LoadStagingJson(raw)
{
	var parsed;
	try
	{
		parsed = JSON.parse(raw);
	}
	catch (err)
	{
		toastr.error(__t('The provided JSON could not be parsed'));
		return;
	}

	if (!parsed || !Array.isArray(parsed.rows))
	{
		toastr.error(__t('The provided JSON does not contain a rows array'));
		return;
	}

	parsed.rows.forEach(function(row)
	{
		if (typeof row.manual_product_override_id === 'undefined')
		{
			row.manual_product_override_id = null;
		}
		if (typeof row.manual_stock_entry_override_id === 'undefined')
		{
			row.manual_stock_entry_override_id = null;
		}
		if (typeof row.product_override_applied === 'undefined')
		{
			row.product_override_applied = false;
		}
		if (typeof row.stock_entry_override_applied === 'undefined')
		{
			row.stock_entry_override_applied = false;
		}
	});

	receiptReviewState.staging = parsed;
	receiptReviewState.lastServerSummary = null;
	UpdateSummary();
	RenderRows();
	ResetStagingJsonInputs();
	toastr.success(__t('Staging JSON loaded'));

	if (NeedsCandidateNameHydration(parsed.rows))
	{
		Grocy.Api.Post('stock/receipt-backfill/review',
			{
				staging: receiptReviewState.staging
			},
			function(result)
			{
				receiptReviewState.staging = result.staging;
				receiptReviewState.lastServerSummary = result.summary || null;
				UpdateSummary();
				RenderRows();
				toastr.info(__t('Candidate product names refreshed from server'));
			}
		);
	}
}

function GetCurrentStagingJson()
{
	return JSON.stringify(receiptReviewState.staging, null, 2);
}

function DownloadCurrentJson()
{
	if (!receiptReviewState.staging)
	{
		return;
	}

	var blob = new Blob([GetCurrentStagingJson()], { type: 'application/json' });
	var url = URL.createObjectURL(blob);
	var link = document.createElement('a');
	link.href = url;
	link.download = 'receipt_staging_overrides.json';
	document.body.appendChild(link);
	link.click();
	document.body.removeChild(link);
	URL.revokeObjectURL(url);
}

var receiptPdfJsLoadPromise = null;

function EnsurePdfJsLoaded()
{
	if (typeof window !== 'undefined' && window.pdfjsLib && window.pdfjsLib.getDocument)
	{
		return Promise.resolve(window.pdfjsLib);
	}

	if (receiptPdfJsLoadPromise)
	{
		return receiptPdfJsLoadPromise;
	}

	receiptPdfJsLoadPromise = new Promise(function(resolve, reject)
	{
		var script = document.createElement('script');
		script.src = 'https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/pdf.min.js';
		script.async = true;
		script.onload = function()
		{
			if (window.pdfjsLib && window.pdfjsLib.getDocument)
			{
				resolve(window.pdfjsLib);
				return;
			}

			reject(new Error(__t('PDF parser library is not available in the browser')));
		};
		script.onerror = function()
		{
			reject(new Error(__t('Failed to load PDF parser library in the browser')));
		};

		document.head.appendChild(script);
	});

	return receiptPdfJsLoadPromise;
}

async function ExtractReceiptTextFromPdf(file)
{
	var pdfjs = await EnsurePdfJsLoaded();

	if (pdfjs.GlobalWorkerOptions)
	{
		pdfjs.GlobalWorkerOptions.workerSrc = 'https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/pdf.worker.min.js';
	}

	var arrayBuffer = await file.arrayBuffer();
	var loadingTask = pdfjs.getDocument({ data: arrayBuffer });
	var pdf = await loadingTask.promise;
	var pageTexts = [];

	for (var pageNumber = 1; pageNumber <= pdf.numPages; pageNumber++)
	{
		var page = await pdf.getPage(pageNumber);
		var content = await page.getTextContent();
		var rowsByY = {};
		var unitWidthSamples = [];

		content.items.forEach(function(item)
		{
			var y = Math.round((item.transform && item.transform[5] ? item.transform[5] : 0) * 2) / 2;
			if (!rowsByY[y])
			{
				rowsByY[y] = [];
			}

			var text = item.str || '';
			if (text.length > 0 && item.width && item.width > 0)
			{
				unitWidthSamples.push(item.width / text.length);
			}

			rowsByY[y].push({
				x: item.transform && item.transform[4] ? item.transform[4] : 0,
				width: item.width || 0,
				text: text
			});
		});

		var unitWidth = 3;
		if (unitWidthSamples.length > 0)
		{
			unitWidthSamples.sort(function(a, b)
			{
				return a - b;
			});
			unitWidth = unitWidthSamples[Math.floor(unitWidthSamples.length / 2)] || 3;
			if (unitWidth < 1)
			{
				unitWidth = 1;
			}
		}

		var sortedYs = Object.keys(rowsByY).map(function(y)
		{
			return parseFloat(y);
		}).sort(function(a, b)
		{
			return b - a;
		});

		sortedYs.forEach(function(y)
		{
			var items = rowsByY[y].sort(function(a, b)
			{
				return a.x - b.x;
			});
			if (items.length === 0)
			{
				return;
			}

				var minX = items[0].x;
				var line = '';
				var cursor = 0;
			items.forEach(function(item)
			{
					var normalizedText = (item.text || '').replace(/\s+/g, ' ');
					if (normalizedText === '')
				{
						return;
				}

					var targetColumn = Math.max(0, Math.round((item.x - minX) / unitWidth));
					if (targetColumn > cursor)
					{
						line += ' '.repeat(targetColumn - cursor);
						cursor = targetColumn;
					}

					line += normalizedText;
					cursor += normalizedText.length;
			});

			line = (line || '').replace(/\s+$/, '');
			if (line.trim() !== '')
			{
				pageTexts.push(line);
			}
		});
	}

	return pageTexts.join('\n');
}

async function ParseUploadedPdfToStaging()
{
	var fileInput = $('#receipt-pdf-file')[0];
	var file = fileInput && fileInput.files && fileInput.files[0] ? fileInput.files[0] : null;
	if (!file)
	{
		toastr.error(__t('Please choose a PDF file first'));
		return;
	}

	try
	{
		$('#parse-uploaded-pdf-button').prop('disabled', true);
		toastr.info(__t('Extracting text from PDF...'));
		var receiptText = await ExtractReceiptTextFromPdf(file);

		Grocy.Api.Post('stock/receipt-backfill/preview-text',
			{
				receipt_text: receiptText,
				days_window: receiptReviewState.staging && receiptReviewState.staging.days_window ? receiptReviewState.staging.days_window : 7
			},
			function(result)
			{
				$('#parse-uploaded-pdf-button').prop('disabled', false);
				ResetReceiptPdfInput();
				ResetStagingJsonInputs();
				receiptReviewState.staging = result.staging;
				receiptReviewState.lastServerSummary = result.summary || null;
				UpdateSummary();
				RenderRows();
				toastr.success(__t('PDF parsed and staging loaded'));
			},
			function(xhr)
			{
				$('#parse-uploaded-pdf-button').prop('disabled', false);
				ResetReceiptPdfInput();
				toastr.error(xhr && xhr.responseJSON && xhr.responseJSON.error_message ? xhr.responseJSON.error_message : __t('Failed to parse uploaded PDF'));
			}
		);
	}
	catch (error)
	{
		$('#parse-uploaded-pdf-button').prop('disabled', false);
		ResetReceiptPdfInput();
		toastr.error(error && error.message ? error.message : __t('Failed to parse uploaded PDF'));
	}
}

$('#receipt-pdf-file').on('change', function()
{
	var file = this.files && this.files[0];
	if (!file)
	{
		ResetReceiptPdfInput();
		return;
	}

	ScheduleReceiptPdfInputAutoClear();
});

$('#staging-json-file').on('change', function()
{
	var file = this.files && this.files[0];
	if (!file)
	{
		ResetStagingJsonInputs();
		return;
	}

	ScheduleStagingJsonInputAutoClear();
});

$('#staging-json-input').on('input', Delay(function()
{
	var value = ($('#staging-json-input').val() || '').trim();
	if (value === '')
	{
		ResetStagingJsonInputs();
		return;
	}

	ScheduleStagingJsonInputAutoClear();
}, Grocy.FormFocusDelay));

$('#load-pasted-staging-button').on('click', function()
{
	LoadStagingJson($('#staging-json-input').val());
});

$('#parse-uploaded-pdf-button').on('click', function()
{
	ParseUploadedPdfToStaging();
});

$('#staging-json-file').on('change', function(e)
{
	var file = e.target.files && e.target.files[0];
	if (!file)
	{
		return;
	}

	var reader = new FileReader();
	reader.onload = function(loadEvent)
	{
		$('#staging-json-input').val(loadEvent.target.result);
		LoadStagingJson(loadEvent.target.result);
	};
	reader.readAsText(file);
});

$('#receipt-review-search').on('keyup', Delay(function()
{
	RenderRows();
}, Grocy.FormFocusDelay));

$(document).on('change', '.manual-product-override-select', function(e)
{
	var lineNumber = parseInt($(e.currentTarget).closest('tr').attr('data-line-number'), 10);
	var row = GetEditableRows().find(function(candidate)
	{
		return candidate.line_number === lineNumber;
	});
	if (!row)
	{
		return;
	}

	var value = ($(e.currentTarget).val() || '').trim();
	row.manual_product_override_id = value === '' ? null : parseInt(value, 10);
	row.product_override_applied = false;
	row.stock_entry_override_applied = false;
});

$(document).on('change', '.manual-stock-entry-override-select', function(e)
{
	var lineNumber = parseInt($(e.currentTarget).closest('tr').attr('data-line-number'), 10);
	var row = GetEditableRows().find(function(candidate)
	{
		return candidate.line_number === lineNumber;
	});
	if (!row)
	{
		return;
	}

	var value = ($(e.currentTarget).val() || '').trim();
	row.manual_stock_entry_override_id = value === '' ? null : value;
	row.stock_entry_override_applied = false;
});

$(document).on('change', '.apply-selected-input', function(e)
{
	var lineNumber = parseInt($(e.currentTarget).closest('tr').attr('data-line-number'), 10);
	var row = GetEditableRows().find(function(candidate)
	{
		return candidate.line_number === lineNumber;
	});
	if (!row)
	{
		return;
	}

	if ((row.status || '') !== 'READY')
	{
		$(e.currentTarget).prop('checked', false);
		row.apply_selected = false;
		return;
	}

	row.apply_selected = $(e.currentTarget).is(':checked');
});

$('#review-on-server-button').on('click', function()
{
	if (!receiptReviewState.staging)
	{
		return;
	}

	Grocy.Api.Post('stock/receipt-backfill/review',
		{
			staging: receiptReviewState.staging
		},
		function(result)
		{
			receiptReviewState.staging = result.staging;
			receiptReviewState.lastServerSummary = result.summary || null;
			UpdateSummary();
			RenderRows();
			toastr.success(__t('Server review completed'));
		},
		function(xhr)
		{
			toastr.error(xhr && xhr.responseJSON && xhr.responseJSON.error_message ? xhr.responseJSON.error_message : __t('Server review failed'));
		}
	);
});

$('#apply-on-server-button').on('click', function()
{
	if (!receiptReviewState.staging)
	{
		return;
	}

	bootbox.confirm({
		message: __t('Apply all READY rows with "Apply" checked?'),
		closeButton: false,
		buttons: {
			confirm: {
				label: __t('Yes'),
				className: 'btn-success'
			},
			cancel: {
				label: __t('No'),
				className: 'btn-danger'
			}
		},
		callback: function(result)
		{
			if (!result)
			{
				return;
			}

			Grocy.Api.Post('stock/receipt-backfill/apply',
				{
					staging: receiptReviewState.staging
				},
				function(apiResult)
				{
					receiptReviewState.staging = apiResult.staging;
					receiptReviewState.lastServerSummary = apiResult.summary || null;
					UpdateSummary();
					RenderRows();

					if (apiResult.errors && apiResult.errors.length > 0)
					{
						toastr.warning(__t('%s row(s) updated, %s error(s)', apiResult.updated_count || 0, apiResult.errors.length));
					}
					else
					{
						toastr.success(__t('%s row(s) updated', apiResult.updated_count || 0));
					}

					ResetStagingJsonInputs();
				},
				function(xhr)
				{
					toastr.error(xhr && xhr.responseJSON && xhr.responseJSON.error_message ? xhr.responseJSON.error_message : __t('Server apply failed'));
				}
			);
		}
	});
});

$('#download-staging-json-button').on('click', function()
{
	DownloadCurrentJson();
});

$('#copy-staging-json-button').on('click', function()
{
	if (!receiptReviewState.staging)
	{
		return;
	}

	var text = GetCurrentStagingJson();
	if (navigator.clipboard && navigator.clipboard.writeText)
	{
		navigator.clipboard.writeText(text).then(function()
		{
			toastr.success(__t('JSON copied to clipboard'));
		});
	}
	else
	{
		$('#staging-json-input').val(text).trigger('focus').trigger('select');
		document.execCommand('copy');
		toastr.success(__t('JSON copied to clipboard'));
	}
});

UpdateSummary();