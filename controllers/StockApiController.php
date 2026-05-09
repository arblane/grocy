<?php

namespace Grocy\Controllers;

use Grocy\Controllers\Users\User;
use Grocy\Services\StockService;
use Grocy\Helpers\WebhookRunner;
use Grocy\Helpers\Grocycode;
use Psr\Http\Message\ResponseInterface as Response;
use Psr\Http\Message\ServerRequestInterface as Request;

class StockApiController extends BaseApiController
{
	private const RECEIPT_STATUS_READY = 'READY';
	private const RECEIPT_STATUS_READY_CREATE_PURCHASE = 'READY_CREATE_PURCHASE';
	private const RECEIPT_STATUS_AMBIGUOUS_PRODUCT = 'AMBIGUOUS_PRODUCT';
	private const RECEIPT_STATUS_AMBIGUOUS_STOCK_ENTRY = 'AMBIGUOUS_STOCK_ENTRY';
	private const RECEIPT_STATUS_STORE_UNMATCHED = 'STORE_UNMATCHED';
	private const RECEIPT_STATUS_NO_PRICE = 'NO_PRICE';
	private const RECEIPT_STATUS_NO_STOCK_ENTRY = 'NO_STOCK_ENTRY';
	private const RECEIPT_STATUS_MISSING_LOCATION = 'MISSING_LOCATION';

	private function normalizeOptionalInt($value): ?int
	{
		if ($value === null || $value === '' || !is_numeric($value))
		{
			return null;
		}

		return intval($value);
	}

	private function normalizeOptionalString($value): ?string
	{
		if ($value === null)
		{
			return null;
		}

		$value = trim(strval($value));
		if ($value === '')
		{
			return null;
		}

		return $value;
	}

	private function computeDateWindow(string $receiptDate, int $daysWindow): array
	{
		$date = new \DateTimeImmutable($receiptDate);
		$start = $date->modify('-' . $daysWindow . ' days')->format('Y-m-d');
		$end = $date->modify('+' . $daysWindow . ' days')->format('Y-m-d');
 
		return [$start, $end];
	}

	private function loadParentProductIdSet(): array
	{
		$parentProductIdSet = [];
		foreach ($this->getDatabase()->products()->where('parent_product_id IS NOT NULL')->fetchAll() as $product)
		{
			$parentProductId = intval($product->parent_product_id);
			if ($parentProductId > 0)
			{
				$parentProductIdSet[$parentProductId] = true;
			}
		}

		return $parentProductIdSet;
	}

	private function composeProductDisplayName(array $product): string
	{
		$parts = [];
		if (!empty($product['name']))
		{
			$parts[] = trim(strval($product['name']));
		}
		if (!empty($product['additional_details']))
		{
			$parts[] = trim(strval($product['additional_details']));
		}
		if (!empty($product['strength']))
		{
			$parts[] = trim(strval($product['strength']));
		}
		if (!empty($product['size']))
		{
			$parts[] = trim(strval($product['size']));
		}
		if (!empty($product['package_configuration']))
		{
			$parts[] = trim(strval($product['package_configuration']));
		}

		$displayName = implode(', ', array_filter($parts, function ($part)
		{
			return $part !== '';
		}));

		if (!empty($product['brand']))
		{
			$brand = trim(strval($product['brand']));
			if ($brand !== '')
			{
				$displayName .= ($displayName === '' ? '' : ' - ') . $brand;
			}
		}

		return $displayName;
	}

	private function loadProductsMapByIds(array $ids, ?array $parentProductIdSet = null): array
	{
		if ($parentProductIdSet === null)
		{
			$parentProductIdSet = $this->loadParentProductIdSet();
		}

		$ids = array_values(array_unique(array_map('intval', array_filter($ids, function ($id)
		{
			return $id !== null && $id !== '' && is_numeric($id);
		}))));

		if (count($ids) === 0)
		{
			return [];
		}

		$result = [];
		foreach ($this->getDatabase()->products()->where('id', $ids)->fetchAll() as $product)
		{
			$additionalDetails = isset($product->additional_details) ? trim(strval($product->additional_details)) : null;
			$strength = isset($product->strength) ? trim(strval($product->strength)) : null;
			$size = isset($product->size) ? trim(strval($product->size)) : null;
			$packageConfiguration = isset($product->package_configuration) ? trim(strval($product->package_configuration)) : null;
			$brand = isset($product->brand) ? trim(strval($product->brand)) : null;
			$productData = [
				'name' => strval($product->name),
				'additional_details' => $additionalDetails,
				'strength' => $strength,
				'size' => $size,
				'package_configuration' => $packageConfiguration,
				'brand' => $brand,
			];
			$displayName = $this->composeProductDisplayName($productData);

			$result[intval($product->id)] = [
				'id' => intval($product->id),
				'name' => strval($product->name),
				'location_id' => $product->location_id === null ? null : intval($product->location_id),
				'additional_details' => $additionalDetails,
				'strength' => $strength,
				'size' => $size,
				'package_configuration' => $packageConfiguration,
				'brand' => $brand,
				'display_name' => $displayName,
				'is_parent_product' => array_key_exists(intval($product->id), $parentProductIdSet),
			];
		}

		return $result;
	}

	private function loadActiveLocationNamesByIds(array $locationIds): array
	{
		$locationIds = array_values(array_unique(array_map('intval', array_filter($locationIds, function ($locationId)
		{
			return $locationId !== null && is_numeric($locationId) && intval($locationId) > 0;
		}))));

		if (count($locationIds) === 0)
		{
			return [];
		}

		$result = [];
		foreach ($this->getDatabase()->locations()->where('id', $locationIds)->where('active = 1')->fetchAll() as $location)
		{
			$result[intval($location->id)] = strval($location->name);
		}

		return $result;
	}

	private function loadStockEntriesForProduct(int $productId, string $receiptDate, int $daysWindow): array
	{
		[$startDate, $endDate] = $this->computeDateWindow($receiptDate, $daysWindow);
		$startDateEscaped = str_replace("'", "''", $startDate);
		$endDateEscaped = str_replace("'", "''", $endDate);
		$productId = intval($productId);

		$sql = "SELECT sl.stock_id, sl.product_id, sl.amount, sl.purchased_date, sl.price, sl.shopping_location_id\n"
			. "FROM stock_log sl\n"
			. "JOIN (\n"
			. "\tSELECT stock_id, MAX(id) AS max_id\n"
			. "\tFROM stock_log\n"
			. "\tWHERE product_id = $productId\n"
			. "\t\tAND transaction_type IN ('purchase', 'inventory-correction', 'stock-edit-new')\n"
			. "\t\tAND undone = 0\n"
			. "\t\tAND amount > 0\n"
			. "\t\tAND DATE(purchased_date) >= '$startDateEscaped'\n"
			. "\t\tAND DATE(purchased_date) <= '$endDateEscaped'\n"
			. "\tGROUP BY stock_id\n"
			. ") latest ON latest.max_id = sl.id\n"
			. "ORDER BY sl.purchased_date DESC, sl.id DESC";

		$entries = [];
		foreach ($this->getDatabaseService()->ExecuteDbQuery($sql)->fetchAll(\PDO::FETCH_OBJ) as $entry)
		{
			$entries[] = [
				'stock_id' => strval($entry->stock_id),
				'product_id' => intval($entry->product_id),
				'amount' => $entry->amount === null ? null : strval($entry->amount),
				'purchased_date' => strval($entry->purchased_date),
				'price' => $entry->price === null ? null : strval($entry->price),
				'shopping_location_id' => $entry->shopping_location_id === null ? null : intval($entry->shopping_location_id),
			];
		}

		return $entries;
	}

	private function loadStockEntryByStockId(string $stockId): ?array
	{
		$entry = $this->getDatabase()->stock()->where('stock_id = ?', $stockId)->fetch();
		if ($entry !== null)
		{
			return [
				'stock_id' => strval($entry->stock_id),
				'product_id' => intval($entry->product_id),
				'amount' => $entry->amount === null ? null : strval($entry->amount),
				'purchased_date' => strval($entry->purchased_date),
				'price' => $entry->price === null ? null : strval($entry->price),
				'shopping_location_id' => $entry->shopping_location_id === null ? null : intval($entry->shopping_location_id),
			];
		}

		$historyEntry =
			$this->getDatabase()->stock_log()
				->where('stock_id = ?', $stockId)
				->where('transaction_type', ['purchase', 'inventory-correction', 'stock-edit-new'])
				->where('undone = ?', 0)
				->where('amount > 0')
				->orderBy('id', 'DESC')
				->fetch();
		if ($historyEntry === null)
		{
			return null;
		}

		return [
			'stock_id' => strval($historyEntry->stock_id),
			'product_id' => intval($historyEntry->product_id),
			'amount' => $historyEntry->amount === null ? null : strval($historyEntry->amount),
			'purchased_date' => strval($historyEntry->purchased_date),
			'price' => $historyEntry->price === null ? null : strval($historyEntry->price),
			'shopping_location_id' => $historyEntry->shopping_location_id === null ? null : intval($historyEntry->shopping_location_id),
		];
	}

	private function formatReceiptBackfillPrice(float $value): string
	{
		return number_format($value, 2, '.', '');
	}

	private function computeReceiptBackfillProposedPrice(array $row, ?array $selectedStockEntry): ?string
	{
		$parsedQuantity = $row['parsed_quantity'] ?? null;
		$numericParsedQuantity = null;
		if ($parsedQuantity !== null && $parsedQuantity !== '' && is_numeric($parsedQuantity))
		{
			$numericParsedQuantity = floatval($parsedQuantity);
			if ($numericParsedQuantity <= 0)
			{
				$numericParsedQuantity = null;
			}
		}

		$parsedUnitPrice = $row['parsed_unit_price'] ?? null;
		if ($parsedUnitPrice !== null && $parsedUnitPrice !== '' && is_numeric($parsedUnitPrice))
		{
			return $this->formatReceiptBackfillPrice(floatval($parsedUnitPrice));
		}

		$parsedTotalPrice = $row['parsed_total_price'] ?? null;
		if ($parsedTotalPrice !== null && $parsedTotalPrice !== '' && is_numeric($parsedTotalPrice))
		{
			$numericTotal = floatval($parsedTotalPrice);
			if ($numericParsedQuantity !== null)
			{
				return $this->formatReceiptBackfillPrice($numericTotal / $numericParsedQuantity);
			}

			if ($selectedStockEntry !== null)
			{
				$entryAmount = $selectedStockEntry['amount'] ?? null;
				if ($entryAmount !== null && $entryAmount !== '' && is_numeric($entryAmount))
				{
					$numericAmount = floatval($entryAmount);
					if ($numericAmount > 0)
					{
						return $this->formatReceiptBackfillPrice($numericTotal / $numericAmount);
					}
				}
			}

			// Last-resort fallback: assume parsed total already represents unit price.
			return $this->formatReceiptBackfillPrice($numericTotal);
		}

		return null;
	}

	private function loadBackfillableStockLogRowsByStockId(string $stockId): array
	{
		$rows = [];
		foreach (
			$this->getDatabase()->stock_log()
				->where('stock_id = ?', $stockId)
				->where('transaction_type', ['purchase', 'inventory-correction', 'stock-edit-new'])
				->where('undone = ?', 0)
				->where('amount > 0')
				->orderBy('id')
				->fetchAll() as $logRow
		) {
			$rows[] = $logRow;
		}

		return $rows;
	}

	private function refreshReceiptBackfillProductCaches(array $productIds): void
	{
		$productIds = array_values(array_unique(array_map('intval', array_filter($productIds, function ($productId)
		{
			return $productId !== null && is_numeric($productId) && intval($productId) > 0;
		}))));

		foreach ($productIds as $productId)
		{
			$this->getDatabaseService()->ExecuteDbStatement('DELETE FROM cache__products_average_price WHERE product_id = ' . $productId);
			$this->getDatabaseService()->ExecuteDbStatement('REPLACE INTO cache__products_average_price (product_id, price) SELECT product_id, price FROM products_average_price WHERE product_id = ' . $productId);

			$this->getDatabaseService()->ExecuteDbStatement('DELETE FROM cache__products_last_purchased WHERE product_id = ' . $productId);
			$this->getDatabaseService()->ExecuteDbStatement('REPLACE INTO cache__products_last_purchased (product_id, amount, best_before_date, purchased_date, price, location_id, shopping_location_id) SELECT product_id, amount, best_before_date, purchased_date, price, location_id, shopping_location_id FROM products_last_purchased WHERE product_id = ' . $productId);
		}
	}

	private function buildCandidateProducts(array $row, array $productsMap, array $parentProductIdSet): array
	{
		$candidateProducts = [];
		if (array_key_exists('candidate_products', $row) && is_array($row['candidate_products']))
		{
			foreach ($row['candidate_products'] as $candidate)
			{
				if (!is_array($candidate) || !array_key_exists('id', $candidate) || !is_numeric($candidate['id']))
				{
					continue;
				}

				$productId = intval($candidate['id']);
				if (array_key_exists($productId, $parentProductIdSet))
				{
					continue;
				}
				$productName = $candidate['name'] ?? ($productsMap[$productId]['name'] ?? null);
				if ($productName === null)
				{
					continue;
				}
				$additionalDetails = null;
				if (array_key_exists('additional_details', $candidate) && $candidate['additional_details'] !== null)
				{
					$additionalDetails = trim(strval($candidate['additional_details']));
				}
				elseif (array_key_exists($productId, $productsMap))
				{
					$additionalDetails = $productsMap[$productId]['additional_details'] ?? null;
				}

				$candidateProducts[$productId] = [
					'id' => $productId,
					'name' => strval($productName),
					'additional_details' => $additionalDetails,
					'strength' => $candidate['strength'] ?? ($productsMap[$productId]['strength'] ?? null),
					'size' => $candidate['size'] ?? ($productsMap[$productId]['size'] ?? null),
					'package_configuration' => $candidate['package_configuration'] ?? ($productsMap[$productId]['package_configuration'] ?? null),
					'brand' => $candidate['brand'] ?? ($productsMap[$productId]['brand'] ?? null),
					'display_name' => ($candidate['display_name'] ?? ($productsMap[$productId]['display_name'] ?? strval($productName))),
					'score' => $candidate['score'] ?? null,
				];
			}
		}

		if (array_key_exists('candidate_product_ids', $row) && is_array($row['candidate_product_ids']))
		{
			foreach ($row['candidate_product_ids'] as $candidateId)
			{
				if (!is_numeric($candidateId))
				{
					continue;
				}

				$productId = intval($candidateId);
				if (array_key_exists($productId, $parentProductIdSet))
				{
					continue;
				}
				if (!array_key_exists($productId, $candidateProducts) && array_key_exists($productId, $productsMap))
				{
					$candidateProducts[$productId] = [
						'id' => $productId,
						'name' => $productsMap[$productId]['name'],
						'additional_details' => $productsMap[$productId]['additional_details'] ?? null,
						'strength' => $productsMap[$productId]['strength'] ?? null,
						'size' => $productsMap[$productId]['size'] ?? null,
						'package_configuration' => $productsMap[$productId]['package_configuration'] ?? null,
						'brand' => $productsMap[$productId]['brand'] ?? null,
						'display_name' => $productsMap[$productId]['display_name'] ?? $productsMap[$productId]['name'],
						'score' => null,
					];
				}
			}
		}

		return array_values($candidateProducts);
	}

	private function extractProductSearchTerms(string $description): array
	{
		$normalized = strtolower(trim($description));
		if ($normalized === '')
		{
			return [];
		}

		$normalized = preg_replace('/[^a-z0-9\s]/', ' ', $normalized);
		if ($normalized === null)
		{
			return [];
		}

		$stopWords = [
			'and', 'the', 'with', 'for', 'from', 'lion', 'food',
			'oz', 'lb', 'pkg', 'pk', 'ct', 'ea', 'style', 'traditional',
		];

		$terms = [];
		foreach (preg_split('/\s+/', $normalized) as $term)
		{
			if (!preg_match('/[a-z]/', $term))
			{
				continue;
			}

			if ($term === '' || strlen($term) < 3 || in_array($term, $stopWords, true))
			{
				continue;
			}
			$terms[$term] = true;
		}

		return array_keys($terms);
	}

	private function searchProductsByDescription(string $description, array $parentProductIdSet, int $limit = 12, string $parsedSize = ''): array
	{
		$terms = $this->extractProductSearchTerms($description);
		if (count($terms) === 0)
		{
			return [];
		}

		$sizeHints = [];
		$parsedSizeNormalized = strtolower(trim($parsedSize));
		if ($parsedSizeNormalized !== '')
		{
			if (preg_match_all('/\d+(?:\.\d+)?|oz|lb|lbs|ct|pk|pkg|gal|qt|pt|ml|l/i', $parsedSizeNormalized, $sizeMatches))
			{
				foreach ($sizeMatches[0] as $sizeToken)
				{
					$token = strtolower(trim(strval($sizeToken)));
					if ($token !== '')
					{
						$sizeHints[$token] = true;
					}
				}
			}
		}

		$matchesByProduct = [];
		foreach ($terms as $term)
		{
			$likePattern = '%' . $term . '%';
			foreach ($this->getDatabase()->products()->where('LOWER(name) LIKE ?', $likePattern)->fetchAll() as $product)
			{
				$productId = intval($product->id);
				if (array_key_exists($productId, $parentProductIdSet))
				{
					continue;
				}
				$additionalDetails = isset($product->additional_details) ? trim(strval($product->additional_details)) : '';
				$strength = isset($product->strength) ? trim(strval($product->strength)) : null;
				$size = isset($product->size) ? trim(strval($product->size)) : null;
				$packageConfiguration = isset($product->package_configuration) ? trim(strval($product->package_configuration)) : null;
				$brand = isset($product->brand) ? trim(strval($product->brand)) : null;
				$productData = [
					'name' => strval($product->name),
					'additional_details' => $additionalDetails === '' ? null : $additionalDetails,
					'strength' => $strength,
					'size' => $size,
					'package_configuration' => $packageConfiguration,
					'brand' => $brand,
				];
				$displayName = $this->composeProductDisplayName($productData);
				if (!array_key_exists($productId, $matchesByProduct))
				{
					$matchesByProduct[$productId] = [
						'id' => $productId,
						'name' => strval($product->name),
						'additional_details' => $additionalDetails === '' ? null : $additionalDetails,
						'strength' => $strength,
						'size' => $size,
						'package_configuration' => $packageConfiguration,
						'brand' => $brand,
						'display_name' => $displayName,
						'matched_terms' => [],
					];
				}
				$matchesByProduct[$productId]['matched_terms'][$term] = true;
			}
		}

		$candidates = [];
		foreach ($matchesByProduct as $product)
		{
			$matchCount = count($product['matched_terms']);
			if ($matchCount === 0)
			{
				continue;
			}

			$baseScore = $matchCount / count($terms);
			$sizeScore = 0.0;
			if (count($sizeHints) > 0)
			{
				$sizeHaystack = strtolower(implode(' ', array_filter([
					strval($product['name'] ?? ''),
					strval($product['additional_details'] ?? ''),
					strval($product['size'] ?? ''),
					strval($product['package_configuration'] ?? ''),
				])));

				$sizeMatched = false;
				foreach (array_keys($sizeHints) as $sizeHint)
				{
					if ($sizeHint === '')
					{
						continue;
					}

					if (strpos($sizeHaystack, $sizeHint) !== false)
					{
						$sizeMatched = true;
						break;
					}
				}

				if ($sizeMatched)
				{
					$sizeScore = 0.12;
				}
			}

			$finalScore = min(1.0, $baseScore + $sizeScore);

			$candidates[] = [
				'id' => intval($product['id']),
				'name' => strval($product['name']),
				'additional_details' => $product['additional_details'] ?? null,
				'strength' => $product['strength'] ?? null,
				'size' => $product['size'] ?? null,
				'package_configuration' => $product['package_configuration'] ?? null,
				'brand' => $product['brand'] ?? null,
				'display_name' => $product['display_name'] ?? strval($product['name']),
				'score' => round($finalScore, 3),
			];
		}

		usort($candidates, function ($a, $b)
		{
			if ($a['score'] === $b['score'])
			{
				return strcmp($a['name'], $b['name']);
			}

			return ($a['score'] > $b['score']) ? -1 : 1;
		});

		return array_slice($candidates, 0, $limit);
	}

	private function autoSelectCandidateProductId(array $candidateProducts): ?int
	{
		if (count($candidateProducts) === 0)
		{
			return null;
		}

		$historyBackedCandidates = array_values(array_filter($candidateProducts, function ($candidate)
		{
			return intval($candidate['stock_entries_in_window'] ?? 0) > 0;
		}));
		if (count($historyBackedCandidates) === 1)
		{
			$candidate = $historyBackedCandidates[0];
			$candidateId = intval($candidate['id'] ?? 0);
			if ($candidateId > 0)
			{
				return $candidateId;
			}
		}

		$top = $candidateProducts[0];
		$topId = intval($top['id'] ?? 0);
		$topScore = is_numeric($top['score'] ?? null) ? floatval($top['score']) : -1.0;
		$topStockCount = intval($top['stock_entries_in_window'] ?? 0);
		if ($topId <= 0)
		{
			return null;
		}

		if (count($candidateProducts) === 1 && $topScore >= 0)
		{
			return $topId;
		}

		$second = $candidateProducts[1] ?? null;
		$secondScore = is_array($second) && is_numeric($second['score'] ?? null) ? floatval($second['score']) : -1.0;
		$secondStockCount = is_array($second) ? intval($second['stock_entries_in_window'] ?? 0) : 0;
		$scoreGap = $topScore - $secondScore;

		if ($topScore >= 0.75 && $scoreGap >= 0.15)
		{
			return $topId;
		}

		if ($topScore >= 0.70 && $scoreGap > 0)
		{
			return $topId;
		}

		if ($topScore >= 0.55 && $scoreGap >= 0.25)
		{
			return $topId;
		}

		if ($topScore >= 0.55 && $scoreGap >= 0.10 && $topStockCount >= max(1, $secondStockCount + 2))
		{
			return $topId;
		}

		if ($topScore >= 0.50 && $scoreGap > 0 && $topStockCount >= max(1, $secondStockCount + 3))
		{
			return $topId;
		}

		if ($topScore >= 0.45 && $topStockCount > 0 && $secondStockCount === 0)
		{
			return $topId;
		}

		if ($topScore >= 0.40 && $scoreGap >= 0.20)
		{
			return $topId;
		}

		return null;
	}

	private function autoSelectStockEntryByReceiptDate(array $candidateStockEntries, string $receiptDate): ?array
	{
		$sameDateEntries = array_values(array_filter($candidateStockEntries, function ($entry) use ($receiptDate)
		{
			$entryDate = strval($entry['purchased_date'] ?? '');
			if ($entryDate === '')
			{
				return false;
			}

			return strpos($entryDate, $receiptDate) === 0;
		}));

		if (count($sameDateEntries) === 1)
		{
			return $sameDateEntries[0];
		}

		return null;
	}

	private function loadProductWindowStats(int $productId, string $receiptDate, int $daysWindow): array
	{
		[$startDate, $endDate] = $this->computeDateWindow($receiptDate, $daysWindow);
		$startDateEscaped = str_replace("'", "''", $startDate);
		$endDateEscaped = str_replace("'", "''", $endDate);
		$productId = intval($productId);

		$countSql = "SELECT COUNT(DISTINCT stock_id) AS stock_entry_count\n"
			. "FROM stock_log\n"
			. "WHERE product_id = $productId\n"
			. "\tAND transaction_type IN ('purchase', 'inventory-correction', 'stock-edit-new')\n"
			. "\tAND undone = 0\n"
			. "\tAND amount > 0\n"
			. "\tAND DATE(purchased_date) >= '$startDateEscaped'\n"
			. "\tAND DATE(purchased_date) <= '$endDateEscaped'";
		$countRow = $this->getDatabaseService()->ExecuteDbQuery($countSql)->fetch(\PDO::FETCH_OBJ);
		$count = $countRow === false || !isset($countRow->stock_entry_count) ? 0 : intval($countRow->stock_entry_count);

		$latestSql = "SELECT purchased_date, price\n"
			. "FROM stock_log\n"
			. "WHERE product_id = $productId\n"
			. "\tAND transaction_type IN ('purchase', 'inventory-correction', 'stock-edit-new')\n"
			. "\tAND undone = 0\n"
			. "\tAND amount > 0\n"
			. "\tAND DATE(purchased_date) >= '$startDateEscaped'\n"
			. "\tAND DATE(purchased_date) <= '$endDateEscaped'\n"
			. "ORDER BY purchased_date DESC, id DESC\n"
			. "LIMIT 1";
		$latest = $this->getDatabaseService()->ExecuteDbQuery($latestSql)->fetch(\PDO::FETCH_OBJ);

		return [
			'stock_entries_in_window' => $count,
			'latest_purchased_date' => $latest === false ? null : strval($latest->purchased_date),
			'latest_price' => $latest === false || $latest->price === null ? null : strval($latest->price),
		];
	}

	private function countStatuses(array $rows): array
	{
		$counts = [];
		foreach ($rows as $row)
		{
			$status = $row['status'] ?? '';
			if ($status === '')
			{
				continue;
			}

			if (!array_key_exists($status, $counts))
			{
				$counts[$status] = 0;
			}
			$counts[$status]++;
		}

		ksort($counts);
		return $counts;
	}

	private function receiptNormalizeWs(string $value): string
	{
		return trim(preg_replace('/\s+/', ' ', $value) ?? $value);
	}

	private function receiptCleanDescription(string $description): string
	{
		$cleaned = $this->receiptNormalizeWs($description);
		if ($cleaned === '')
		{
			return '';
		}

		// Remove trailing column artifacts that can leak into description after PDF text reconstruction.
		$cleaned = preg_replace('/\s+\$?\d+\.\d{2}(?:\/LB)?(?:\s+\$?\d+\.\d{2})?\s*$/i', '', $cleaned) ?? $cleaned;
		$cleaned = preg_replace('/\s+\d+(?:\.\d+)?\s+\$?\d+\.\d{2}(?:\/LB)?\s*$/i', '', $cleaned) ?? $cleaned;
		$cleaned = preg_replace('/\s+\d+(?:\.\d+)?\s*(?:oz|lb|lbs|ct|ea|pk|pkg|gal|qt|pt|ml|l)\s*$/i', '', $cleaned) ?? $cleaned;
		$cleaned = preg_replace('/\s+\d+(?:\.\d+)?\s*$/i', '', $cleaned) ?? $cleaned;

		return $this->receiptNormalizeWs($cleaned);
	}

	private function receiptIsSkipLine(string $text): bool
	{
		$trimmed = trim($text);
		if ($trimmed === '')
		{
			return true;
		}

		$keywords = [
			'subtotal', 'total savings', 'sales tax', 'pickup fee', 'service fee',
			'grocery total', 'payment by', 'grocery total due', 'amount charged',
			'specials total', 'weekly specials', 'your savings', 'standard substitution',
			'*** pickup ***', 'customer care:', 'order information', 'order date',
			'pickup date', 'order id',
		];

		$lower = strtolower($trimmed);
		foreach ($keywords as $keyword)
		{
			if (strpos($lower, $keyword) !== false)
			{
				return true;
			}
		}

		return false;
	}

	private function receiptFindColumnPositions(array $lines): ?array
	{
		foreach ($lines as $line)
		{
			if (strpos($line, 'Size') !== false && strpos($line, 'Delivered') !== false && strpos($line, 'Item Price') !== false && strpos($line, 'Total') !== false)
			{
				$sizePos = strpos($line, 'Size');
				if ($sizePos === false)
				{
					continue;
				}

				return [
					'size' => $sizePos,
					'delivered' => strpos($line, 'Delivered') ?: 0,
					'item_price' => strpos($line, 'Item Price') ?: 0,
					'specials' => strpos($line, 'Specials') ?: 0,
					'coupon' => strpos($line, 'Coupon(s)') ?: 0,
					'total' => strrpos($line, 'Total') ?: 0,
				];
			}
		}

		return null;
	}

	private function receiptExtractColumns(string $line, array $cols): array
	{
		$sorted = $cols;
		asort($sorted);

		$result = [];
		$keys = array_keys($sorted);
		for ($i = 0; $i < count($keys); $i++)
		{
			$name = $keys[$i];
			$start = intval($sorted[$name]);
			$end = $i + 1 < count($keys) ? intval($sorted[$keys[$i + 1]]) : strlen($line);
			$result[$name] = strlen($line) > $start ? trim(substr($line, $start, max(0, $end - $start))) : '';
		}

		$result['description'] = strlen($line) > intval($cols['size']) ? trim(substr($line, 0, intval($cols['size']))) : trim($line);
		return $result;
	}

	private function receiptHasNumericData(array $colData): bool
	{
		foreach ($colData as $key => $value)
		{
			if ($key === 'description')
			{
				continue;
			}

			if (preg_match('/\d/', strval($value)))
			{
				return true;
			}
		}

		return false;
	}

	private function parseFoodLionReceiptText(string $text): array
	{
		$lines = preg_split('/\r\n|\r|\n/', $text) ?: [];
		$storeText = '';
		$storeAddress = '';
		$receiptDate = '';
		$pickupDate = '';
		$orderDate = '';

		for ($i = 0; $i < count($lines); $i++)
		{
			$line = strval($lines[$i]);
			$trimmed = trim($line);
			if ($storeText === '' && preg_match('/food\s*lion/i', $trimmed))
			{
				$storeText = 'Food Lion';
				if ($i + 1 < count($lines))
				{
					$storeAddress = trim(strval($lines[$i + 1]));
				}
			}

			if (preg_match('/Pickup\s+Date\s+(\d{2}\/\d{2}\/\d{4})/i', $line, $matches))
			{
				$date = \DateTimeImmutable::createFromFormat('m/d/Y', $matches[1]);
				if ($date !== false)
				{
					$pickupDate = $date->format('Y-m-d');
				}
			}

			if (preg_match('/Order\s+Date\s+(\d{2}\/\d{2}\/\d{4})/i', $line, $matches))
			{
				$date = \DateTimeImmutable::createFromFormat('m/d/Y', $matches[1]);
				if ($date !== false)
				{
					$orderDate = $date->format('Y-m-d');
				}
			}
		}

		$receiptDate = $pickupDate !== '' ? $pickupDate : $orderDate;
		$dateCandidates = [];
		if ($pickupDate !== '')
		{
			$dateCandidates[] = $pickupDate;
		}
		if ($orderDate !== '' && $orderDate !== $pickupDate)
		{
			$dateCandidates[] = $orderDate;
		}

		$cols = $this->receiptFindColumnPositions($lines);
		$items = [];
		$inStockSection = false;
		$currentSection = '';

		for ($i = 0; $i < count($lines); $i++)
		{
			$line = strval($lines[$i]);
			$lineNumber = $i + 1;
			$stripped = trim($line);

			if (preg_match('/^\s*In Stock\b/', $line) && strpos($line, 'Size') !== false)
			{
				$inStockSection = true;
				continue;
			}
			if (!$inStockSection)
			{
				continue;
			}
			if (strpos($line, 'Amount charged may be lower') !== false || strpos($line, '*** PICKUP ***') !== false)
			{
				break;
			}
			if ($this->receiptIsSkipLine($line))
			{
				continue;
			}
			if ($stripped === '')
			{
				continue;
			}

			$description = $stripped;
			$sizeVal = '';
			$deliveredVal = '';
			$itemPriceVal = '';
			$specialsVal = '';
			$totalVal = '';
			if ($cols !== null)
			{
				$colData = $this->receiptExtractColumns($line, $cols);
				$description = trim(strval($colData['description'] ?? ''));
				$sizeVal = trim(strval($colData['size'] ?? ''));
				$deliveredVal = trim(strval($colData['delivered'] ?? ''));
				$itemPriceVal = trim(strval($colData['item_price'] ?? ''));
				$specialsVal = trim(strval($colData['specials'] ?? ''));
				$totalVal = trim(strval($colData['total'] ?? ''));
			}

			if ($description === '')
			{
				continue;
			}

			$valueCols = [
				'size' => $sizeVal,
				'delivered' => $deliveredVal,
				'item_price' => $itemPriceVal,
				'specials' => $specialsVal,
				'total' => $totalVal,
			];
			if (!$this->receiptHasNumericData($valueCols) && strlen($description) < 60)
			{
				$currentSection = $description;
				continue;
			}

			$parsedUnitPrice = null;
			$parsedTotalPrice = null;
			$proposedPrice = null;

			if (preg_match('/(\d+\.\d{2})\/LB/i', $itemPriceVal, $unitMatches))
			{
				$parsedUnitPrice = $unitMatches[1] . '/LB';
				if (preg_match('/\$?(\d+\.\d{2})/', $totalVal, $totalMatches))
				{
					$parsedTotalPrice = $totalMatches[1];
				}
				$proposedPrice = $parsedTotalPrice;
			}
			else
			{
				$specialsPrice = null;
				if (preg_match('/\$?(\d+\.\d{2})/', $itemPriceVal, $itemMatches))
				{
					$parsedUnitPrice = $itemMatches[1];
				}
				if (preg_match('/\$?(\d+\.\d{2})/', $specialsVal, $specialsMatches))
				{
					$specialsPrice = $specialsMatches[1];
				}
				if ($specialsPrice !== null)
				{
					$parsedUnitPrice = $specialsPrice;
				}
				if (preg_match('/\$?(\d+\.\d{2})/', $totalVal, $totalMatches))
				{
					$parsedTotalPrice = $totalMatches[1];
				}
				$proposedPrice = $parsedUnitPrice;
			}

			$parsedDescription = $this->receiptCleanDescription($description);
			if ($parsedDescription === '')
			{
				$parsedDescription = $this->receiptNormalizeWs($description);
			}

			$items[] = [
				'line_number' => $lineNumber,
				'raw_text' => $line,
				'section_name' => $currentSection,
				'parsed_description' => $parsedDescription,
				'parsed_size' => $this->receiptNormalizeWs($sizeVal),
				'parsed_quantity' => $this->receiptNormalizeWs($deliveredVal),
				'parsed_unit_price' => $parsedUnitPrice,
				'parsed_total_price' => $parsedTotalPrice,
				'proposed_price' => $proposedPrice,
			];
		}

		return [
			'store_text' => $storeText,
			'receipt_date' => $receiptDate,
			'date_candidates' => $dateCandidates,
			'store_address' => $storeAddress,
			'items' => $items,
		];
	}

	private function matchShoppingLocationByStoreText(string $storeText): array
	{
		if ($storeText === '')
		{
			return [null, ''];
		}

		$target = strtolower(trim($storeText));
		$locations = $this->getDatabase()->shopping_locations()->orderBy('id')->fetchAll();

		foreach ($locations as $location)
		{
			$name = strtolower(trim(strval($location->name)));
			if ($name === $target)
			{
				return [intval($location->id), strval($location->name)];
			}
		}

		foreach ($locations as $location)
		{
			$name = strtolower(trim(strval($location->name)));
			if (strpos($name, $target) !== false || strpos($target, $name) !== false)
			{
				return [intval($location->id), strval($location->name)];
			}
		}

		return [null, ''];
	}

	public function ReceiptBackfillPreviewFromText(Request $request, Response $response, array $args)
	{
		User::checkPermission($request, User::PERMISSION_STOCK_PURCHASE);

		try
		{
			$requestBody = $request->getParsedBody();
			if (!is_array($requestBody))
			{
				throw new \Exception('Invalid request body');
			}

			$receiptText = strval($requestBody['receipt_text'] ?? '');
			if (trim($receiptText) === '')
			{
				throw new \Exception('receipt_text is required');
			}

			$daysWindow = 7;
			if (array_key_exists('days_window', $requestBody) && is_numeric($requestBody['days_window']))
			{
				$daysWindow = intval($requestBody['days_window']);
			}

			$parsed = $this->parseFoodLionReceiptText($receiptText);
			$dateCandidates = [];
			if (array_key_exists('date_candidates', $parsed) && is_array($parsed['date_candidates']))
			{
				foreach ($parsed['date_candidates'] as $candidateDate)
				{
					$candidateDate = strval($candidateDate);
					if ($candidateDate !== '')
					{
						$dateCandidates[] = $candidateDate;
					}
				}
			}

			$receiptDate = strval($parsed['receipt_date'] ?? '');
			if ($receiptDate !== '' && !in_array($receiptDate, $dateCandidates, true))
			{
				array_unshift($dateCandidates, $receiptDate);
			}

			if (count($dateCandidates) === 0)
			{
				throw new \Exception('Could not detect receipt date from uploaded PDF text');
			}

			$storeText = strval($parsed['store_text'] ?? '');
			[$matchedStoreId, $matchedStoreName] = $this->matchShoppingLocationByStoreText($storeText);

			$bestResult = null;
			$bestRank = null;
			$bestReceiptDate = null;
			foreach ($dateCandidates as $candidateDate)
			{
				$rows = [];
				foreach ($parsed['items'] as $item)
				{
					$rows[] = [
						'line_number' => intval($item['line_number'] ?? 0),
						'raw_text' => strval($item['raw_text'] ?? ''),
						'section_name' => strval($item['section_name'] ?? ''),
						'parsed_description' => strval($item['parsed_description'] ?? ''),
						'parsed_size' => strval($item['parsed_size'] ?? ''),
						'parsed_quantity' => strval($item['parsed_quantity'] ?? ''),
						'parsed_unit_price' => $item['parsed_unit_price'] ?? null,
						'parsed_total_price' => $item['parsed_total_price'] ?? null,
						'proposed_price' => $item['proposed_price'] ?? null,
						'parsed_store_text' => $storeText,
						'parsed_receipt_date' => $candidateDate,
						'matched_store_id' => $matchedStoreId,
						'matched_store_name' => $matchedStoreName,
						'manual_product_override_id' => null,
						'manual_stock_entry_override_id' => null,
						'apply_selected' => false,
					];
				}

				$staging = [
					'format' => 'food-lion-pdf-text',
					'store_text' => $storeText,
					'receipt_date' => $candidateDate,
					'store_address' => strval($parsed['store_address'] ?? ''),
					'matched_store_id' => $matchedStoreId,
					'matched_store_name' => $matchedStoreName,
					'days_window' => $daysWindow,
					'rows' => $rows,
				];

				$result = $this->reviewStaging($staging, $daysWindow);
				$statusCounts = $result['summary']['status_counts'] ?? [];
				$readyCount = intval($result['summary']['ready'] ?? 0);
				$ambiguousProductCount = intval($statusCounts[self::RECEIPT_STATUS_AMBIGUOUS_PRODUCT] ?? 0);
				$noStockEntryCount = intval($statusCounts[self::RECEIPT_STATUS_NO_STOCK_ENTRY] ?? 0);
				$rank = [$readyCount, -$ambiguousProductCount, -$noStockEntryCount];

				if ($bestRank === null || $rank > $bestRank)
				{
					$bestRank = $rank;
					$bestResult = $result;
					$bestReceiptDate = $candidateDate;
				}
			}

			if ($bestResult === null)
			{
				throw new \Exception('Unable to evaluate uploaded PDF rows');
			}

			$bestResult['summary']['selected_receipt_date'] = $bestReceiptDate;
			$bestResult['summary']['candidate_receipt_dates'] = $dateCandidates;

			return $this->ApiResponse($response, $bestResult);
		}
		catch (\Exception $ex)
		{
			return $this->GenericErrorResponse($response, $ex->getMessage());
		}
	}

	private function reviewStaging(array $staging, ?int $daysWindowOverride = null): array
	{
		$rows = $staging['rows'] ?? [];
		if (!is_array($rows))
		{
			throw new \Exception('staging.rows must be an array');
		}

		$daysWindow = $daysWindowOverride;
		if ($daysWindow === null)
		{
			$daysWindow = array_key_exists('days_window', $staging) && is_numeric($staging['days_window']) ? intval($staging['days_window']) : 7;
		}

		$storeMatched = array_key_exists('matched_store_id', $staging) && $staging['matched_store_id'] !== null;
		$storeText = strval($staging['store_text'] ?? '');
		$receiptDate = strval($staging['receipt_date'] ?? '');
		if ($receiptDate === '')
		{
			throw new \Exception('staging.receipt_date is required');
		}

		$productIdSet = [];
		$parentProductIdSet = $this->loadParentProductIdSet();
		$searchedCandidatesByLine = [];
		foreach ($rows as $row)
		{
			if (!is_array($row))
			{
				continue;
			}

			$lineNumber = intval($row['line_number'] ?? 0);
			$searchedCandidates = $this->searchProductsByDescription(
				strval($row['parsed_description'] ?? ''),
				$parentProductIdSet,
				12,
				strval($row['parsed_size'] ?? '')
			);
			$searchedCandidatesByLine[$lineNumber] = $searchedCandidates;
			foreach ($searchedCandidates as $searchedCandidate)
			{
				if (array_key_exists('id', $searchedCandidate) && is_numeric($searchedCandidate['id']))
				{
					$productIdSet[] = intval($searchedCandidate['id']);
				}
			}

			if (array_key_exists('candidate_product_ids', $row) && is_array($row['candidate_product_ids']))
			{
				foreach ($row['candidate_product_ids'] as $candidateId)
				{
					if (is_numeric($candidateId))
					{
						$productIdSet[] = intval($candidateId);
					}
				}
			}

			if (array_key_exists('manual_product_override_id', $row) && is_numeric($row['manual_product_override_id']))
			{
				$productIdSet[] = intval($row['manual_product_override_id']);
			}

			if (array_key_exists('selected_product_id', $row) && is_numeric($row['selected_product_id']))
			{
				$productIdSet[] = intval($row['selected_product_id']);
			}
		}

		$productsMap = $this->loadProductsMapByIds($productIdSet, $parentProductIdSet);
		$locationNamesById = $this->loadActiveLocationNamesByIds(array_map(function ($product)
		{
			return $product['location_id'] ?? null;
		}, array_values($productsMap)));
		$productWindowStatsCache = [];

		$reviewedRows = [];
		foreach ($rows as $row)
		{
			if (!is_array($row))
			{
				continue;
			}

			$row['proposed_price'] = $this->computeReceiptBackfillProposedPrice($row, null);

			$candidateProducts = $this->buildCandidateProducts($row, $productsMap, $parentProductIdSet);
			$lineNumber = intval($row['line_number'] ?? 0);
			if (array_key_exists($lineNumber, $searchedCandidatesByLine))
			{
				foreach ($searchedCandidatesByLine[$lineNumber] as $searchedCandidate)
				{
					$productId = intval($searchedCandidate['id'] ?? 0);
					if ($productId <= 0)
					{
						continue;
					}
					if (array_key_exists($productId, $parentProductIdSet))
					{
						continue;
					}

					$existingIndex = null;
					for ($i = 0; $i < count($candidateProducts); $i++)
					{
						if (intval($candidateProducts[$i]['id']) === $productId)
						{
							$existingIndex = $i;
							break;
						}
					}

					if ($existingIndex === null)
					{
						$candidateProducts[] = [
							'id' => $productId,
							'name' => $searchedCandidate['name'] ?? ($productsMap[$productId]['name'] ?? ''),
							'additional_details' => $searchedCandidate['additional_details'] ?? ($productsMap[$productId]['additional_details'] ?? null),
							'strength' => $searchedCandidate['strength'] ?? ($productsMap[$productId]['strength'] ?? null),
							'size' => $searchedCandidate['size'] ?? ($productsMap[$productId]['size'] ?? null),
							'package_configuration' => $searchedCandidate['package_configuration'] ?? ($productsMap[$productId]['package_configuration'] ?? null),
							'brand' => $searchedCandidate['brand'] ?? ($productsMap[$productId]['brand'] ?? null),
							'display_name' => $searchedCandidate['display_name'] ?? ($productsMap[$productId]['display_name'] ?? ($searchedCandidate['name'] ?? ($productsMap[$productId]['name'] ?? ''))),
							'score' => $searchedCandidate['score'] ?? null,
						];
					}
					elseif (($candidateProducts[$existingIndex]['score'] ?? null) === null && array_key_exists('score', $searchedCandidate))
					{
						$candidateProducts[$existingIndex]['score'] = $searchedCandidate['score'];
					}
				}
			}

			foreach ($candidateProducts as &$candidateProduct)
			{
				$candidateProductId = intval($candidateProduct['id']);
				if ($candidateProductId <= 0)
				{
					continue;
				}

				if (!array_key_exists($candidateProductId, $productWindowStatsCache))
				{
					$productWindowStatsCache[$candidateProductId] = $this->loadProductWindowStats($candidateProductId, $receiptDate, $daysWindow);
				}

				$candidateProduct['stock_entries_in_window'] = $productWindowStatsCache[$candidateProductId]['stock_entries_in_window'];
				$candidateProduct['latest_purchased_date'] = $productWindowStatsCache[$candidateProductId]['latest_purchased_date'];
				$candidateProduct['latest_price'] = $productWindowStatsCache[$candidateProductId]['latest_price'];
			}
			unset($candidateProduct);

			usort($candidateProducts, function ($a, $b)
			{
				$scoreA = $a['score'] ?? -1;
				$scoreB = $b['score'] ?? -1;
				if ($scoreA !== $scoreB)
				{
					return ($scoreA > $scoreB) ? -1 : 1;
				}

				$stockCountA = intval($a['stock_entries_in_window'] ?? 0);
				$stockCountB = intval($b['stock_entries_in_window'] ?? 0);
				if ($stockCountA !== $stockCountB)
				{
					return ($stockCountA > $stockCountB) ? -1 : 1;
				}

				return strcmp(strval($a['name'] ?? ''), strval($b['name'] ?? ''));
			});
			$candidateProductIds = array_values(array_map(function ($candidate)
			{
				return intval($candidate['id']);
			}, $candidateProducts));

			$manualProductOverrideId = $this->normalizeOptionalInt($row['manual_product_override_id'] ?? null);
			$manualStockEntryOverrideId = $this->normalizeOptionalString($row['manual_stock_entry_override_id'] ?? null);

			$selectedProductId = null;
			$selectedProductName = '';
			$productOverrideApplied = false;
			$status = self::RECEIPT_STATUS_AMBIGUOUS_PRODUCT;
			$statusReason = '';

			if (!$storeMatched)
			{
				$status = self::RECEIPT_STATUS_STORE_UNMATCHED;
				$statusReason = 'no shopping_location matches ' . $storeText;
			}
			else
			{
				if ($manualProductOverrideId !== null)
				{
					if (!array_key_exists($manualProductOverrideId, $productsMap))
					{
						$status = self::RECEIPT_STATUS_AMBIGUOUS_PRODUCT;
						$statusReason = 'manual_product_override_id ' . $manualProductOverrideId . ' was not found';
					}
					elseif (array_key_exists($manualProductOverrideId, $parentProductIdSet))
					{
						$status = self::RECEIPT_STATUS_AMBIGUOUS_PRODUCT;
						$statusReason = 'manual_product_override_id ' . $manualProductOverrideId . ' is a parent product and not eligible';
					}
					else
					{
						$selectedProductId = $manualProductOverrideId;
						$selectedProductName = $productsMap[$selectedProductId]['name'];
						$productOverrideApplied = true;
						$status = self::RECEIPT_STATUS_READY;
					}
				}
				elseif (
					array_key_exists('selected_product_id', $row)
					&& is_numeric($row['selected_product_id'])
					&& array_key_exists(intval($row['selected_product_id']), $productsMap)
					&& !array_key_exists(intval($row['selected_product_id']), $parentProductIdSet)
				)
				{
					$selectedProductId = intval($row['selected_product_id']);
					$selectedProductName = $productsMap[$selectedProductId]['name'];
					$status = self::RECEIPT_STATUS_READY;
				}
				elseif (count($candidateProductIds) == 1)
				{
					$selectedProductId = $candidateProductIds[0];
					$selectedProductName = $productsMap[$selectedProductId]['name'] ?? '';
					$status = self::RECEIPT_STATUS_READY;
				}
				else
				{
					$autoSelectedProductId = $this->autoSelectCandidateProductId($candidateProducts);
					if ($autoSelectedProductId !== null && array_key_exists($autoSelectedProductId, $productsMap))
					{
						$selectedProductId = $autoSelectedProductId;
						$selectedProductName = $productsMap[$selectedProductId]['name'];
						$status = self::RECEIPT_STATUS_READY;
						$statusReason = '';
					}
					else
					{
						$status = self::RECEIPT_STATUS_AMBIGUOUS_PRODUCT;
						$statusReason = count($candidateProductIds) > 0 ? 'multiple candidate products require selection' : 'no product candidates found';
					}
				}
			}

			$candidateStockEntries = [];
			$candidateStockEntryIds = [];
			$selectedStockEntryId = null;
			$currentStockEntryPrice = null;
			$currentStockEntryAmount = null;
			$currentStockEntryStoreId = null;
			$proposedLocationId = null;
			$proposedLocationName = null;
			$stockEntryOverrideApplied = false;

			if ($status === self::RECEIPT_STATUS_READY && $selectedProductId !== null)
			{
				$proposedLocationId = $this->normalizeOptionalInt($productsMap[$selectedProductId]['location_id'] ?? null);
				if ($proposedLocationId !== null && array_key_exists($proposedLocationId, $locationNamesById))
				{
					$proposedLocationName = $locationNamesById[$proposedLocationId];
				}

				$candidateStockEntries = $this->loadStockEntriesForProduct($selectedProductId, $receiptDate, $daysWindow);
				$candidateStockEntryIds = array_values(array_map(function ($entry)
				{
					return strval($entry['stock_id']);
				}, $candidateStockEntries));

				if ($manualStockEntryOverrideId !== null)
				{
					$explicitEntry = null;
					foreach ($candidateStockEntries as $entry)
					{
						if ($entry['stock_id'] === $manualStockEntryOverrideId)
						{
							$explicitEntry = $entry;
							break;
						}
					}

					if ($explicitEntry === null)
					{
						$explicitEntry = $this->loadStockEntryByStockId($manualStockEntryOverrideId);
					}

					if ($explicitEntry === null)
					{
						$status = self::RECEIPT_STATUS_AMBIGUOUS_STOCK_ENTRY;
						$statusReason = 'manual_stock_entry_override_id ' . $manualStockEntryOverrideId . ' was not found';
					}
					elseif (intval($explicitEntry['product_id']) !== intval($selectedProductId))
					{
						$status = self::RECEIPT_STATUS_AMBIGUOUS_STOCK_ENTRY;
						$statusReason = 'manual_stock_entry_override_id ' . $manualStockEntryOverrideId . ' does not belong to selected product';
					}
					else
					{
						$selectedStockEntryId = strval($explicitEntry['stock_id']);
						$currentStockEntryAmount = $explicitEntry['amount'] ?? null;
						$currentStockEntryPrice = $explicitEntry['price'];
						$currentStockEntryStoreId = $explicitEntry['shopping_location_id'];
						$stockEntryOverrideApplied = true;

						if (!in_array($selectedStockEntryId, $candidateStockEntryIds))
						{
							array_unshift($candidateStockEntryIds, $selectedStockEntryId);
							array_unshift($candidateStockEntries, $explicitEntry);
						}

						$row['proposed_price'] = $this->computeReceiptBackfillProposedPrice($row, $explicitEntry);
						if ($row['proposed_price'] !== null && $row['proposed_price'] !== '')
						{
							$status = self::RECEIPT_STATUS_READY;
							$statusReason = '';
						}
						else
						{
							$status = self::RECEIPT_STATUS_NO_PRICE;
							$statusReason = 'no price extracted from receipt';
						}
					}
				}
				elseif (count($candidateStockEntries) === 0)
				{
					$row['proposed_store_id'] = $this->normalizeOptionalInt($row['proposed_store_id'] ?? $row['matched_store_id'] ?? $staging['matched_store_id'] ?? null);

					if ($proposedLocationId === null || !array_key_exists($proposedLocationId, $locationNamesById))
					{
						$status = self::RECEIPT_STATUS_MISSING_LOCATION;
						$statusReason = 'selected product has no active default location';
					}
					elseif (($row['proposed_price'] ?? null) === null || ($row['proposed_price'] ?? '') === '')
					{
						$status = self::RECEIPT_STATUS_NO_PRICE;
						$statusReason = 'no price extracted from receipt';
					}
					else
					{
						$status = self::RECEIPT_STATUS_READY_CREATE_PURCHASE;
						$statusReason = '';
					}
				}
				elseif (count($candidateStockEntries) === 1)
				{
					$selectedStockEntryId = $candidateStockEntries[0]['stock_id'];
					$currentStockEntryAmount = $candidateStockEntries[0]['amount'] ?? null;
					$currentStockEntryPrice = $candidateStockEntries[0]['price'];
					$currentStockEntryStoreId = $candidateStockEntries[0]['shopping_location_id'];

					$row['proposed_price'] = $this->computeReceiptBackfillProposedPrice($row, $candidateStockEntries[0]);
					if ($row['proposed_price'] !== null && $row['proposed_price'] !== '')
					{
						$status = self::RECEIPT_STATUS_READY;
						$statusReason = '';
					}
					else
					{
						$status = self::RECEIPT_STATUS_NO_PRICE;
						$statusReason = 'no price extracted from receipt';
					}
				}
				else
				{
					$autoSelectedStockEntry = $this->autoSelectStockEntryByReceiptDate($candidateStockEntries, $receiptDate);
					if ($autoSelectedStockEntry !== null)
					{
						$selectedStockEntryId = strval($autoSelectedStockEntry['stock_id']);
						$currentStockEntryAmount = $autoSelectedStockEntry['amount'] ?? null;
						$currentStockEntryPrice = $autoSelectedStockEntry['price'];
						$currentStockEntryStoreId = $autoSelectedStockEntry['shopping_location_id'];

						$row['proposed_price'] = $this->computeReceiptBackfillProposedPrice($row, $autoSelectedStockEntry);
						if ($row['proposed_price'] !== null && $row['proposed_price'] !== '')
						{
							$status = self::RECEIPT_STATUS_READY;
							$statusReason = '';
						}
						else
						{
							$status = self::RECEIPT_STATUS_NO_PRICE;
							$statusReason = 'no price extracted from receipt';
						}
					}
					else
					{
						$status = self::RECEIPT_STATUS_AMBIGUOUS_STOCK_ENTRY;
						$statusReason = count($candidateStockEntries) . ' stock entries in window (need manual selection)';
					}
				}
			}

			$row['candidate_product_ids'] = $candidateProductIds;
			$row['candidate_products'] = $candidateProducts;
			$row['manual_product_override_id'] = $manualProductOverrideId;
			$row['selected_product_id'] = $selectedProductId;
			$row['selected_product_name'] = $selectedProductName;
			$row['candidate_stock_entry_ids'] = $candidateStockEntryIds;
			$row['candidate_stock_entries'] = $candidateStockEntries;
			$row['manual_stock_entry_override_id'] = $manualStockEntryOverrideId;
			$row['selected_stock_entry_id'] = $selectedStockEntryId;
			$row['current_stock_entry_amount'] = $currentStockEntryAmount;
			$row['current_stock_entry_price'] = $currentStockEntryPrice;
			$row['current_stock_entry_store_id'] = $currentStockEntryStoreId;
			$row['proposed_location_id'] = $proposedLocationId;
			$row['proposed_location_name'] = $proposedLocationName;
			$row['product_override_applied'] = $productOverrideApplied;
			$row['stock_entry_override_applied'] = $stockEntryOverrideApplied;
			$row['status'] = $status;
			$row['status_reason'] = $statusReason;
			if (!array_key_exists('confidence_score', $row))
			{
				$row['confidence_score'] = 0.0;
			}
			$row['apply_selected'] = (
				$status === self::RECEIPT_STATUS_READY
				|| $status === self::RECEIPT_STATUS_READY_CREATE_PURCHASE
			) ? boolval($row['apply_selected'] ?? false) : false;

			$reviewedRows[] = $row;
		}

		$staging['days_window'] = $daysWindow;
		$staging['rows'] = $reviewedRows;

		return [
			'staging' => $staging,
			'summary' => [
				'rows' => count($reviewedRows),
				'ready' => count(array_filter($reviewedRows, function ($row)
				{
					return ($row['status'] ?? '') === self::RECEIPT_STATUS_READY;
				})),
				'status_counts' => $this->countStatuses($reviewedRows),
			],
		];
	}
	private function TryParseConsumeRequestBodyWithLocalizedAmount(Request $request)
	{
		$bodyStream = $request->getBody();
		if ($bodyStream->isSeekable())
		{
			$bodyStream->rewind();
		}

		$rawBody = $bodyStream->getContents();
		if ($bodyStream->isSeekable())
		{
			$bodyStream->rewind();
		}

		if (empty($rawBody))
		{
			return null;
		}

		$normalizedBody = preg_replace('/("amount"\s*:\s*-?\d+),(\d+)/', '$1.$2', $rawBody);
		if ($normalizedBody === null || $normalizedBody === $rawBody)
		{
			return null;
		}

		$decodedBody = json_decode($normalizedBody, true);
		if (json_last_error() !== JSON_ERROR_NONE || !is_array($decodedBody))
		{
			return null;
		}

		return $decodedBody;
	}

	public function ReceiptBackfillReview(Request $request, Response $response, array $args)
	{
		User::checkPermission($request, User::PERMISSION_STOCK_PURCHASE);

		try
		{
			$requestBody = $request->getParsedBody();
			if (!is_array($requestBody))
			{
				throw new \Exception('Invalid request body');
			}
			if (!array_key_exists('staging', $requestBody) || !is_array($requestBody['staging']))
			{
				throw new \Exception('staging payload is required');
			}

			$daysWindow = null;
			if (array_key_exists('days_window', $requestBody) && is_numeric($requestBody['days_window']))
			{
				$daysWindow = intval($requestBody['days_window']);
			}

			$result = $this->reviewStaging($requestBody['staging'], $daysWindow);
			return $this->ApiResponse($response, $result);
		}
		catch (\Exception $ex)
		{
			return $this->GenericErrorResponse($response, $ex->getMessage());
		}
	}

	public function ReceiptBackfillApply(Request $request, Response $response, array $args)
	{
		User::checkPermission($request, User::PERMISSION_STOCK_PURCHASE);

		try
		{
			$requestBody = $request->getParsedBody();
			if (!is_array($requestBody))
			{
				throw new \Exception('Invalid request body');
			}
			if (!array_key_exists('staging', $requestBody) || !is_array($requestBody['staging']))
			{
				throw new \Exception('staging payload is required');
			}

			$daysWindow = null;
			if (array_key_exists('days_window', $requestBody) && is_numeric($requestBody['days_window']))
			{
				$daysWindow = intval($requestBody['days_window']);
			}

			$reviewResult = $this->reviewStaging($requestBody['staging'], $daysWindow);
			$rows = $reviewResult['staging']['rows'];
			$defaultStoreId = $this->normalizeOptionalInt($reviewResult['staging']['matched_store_id'] ?? null);

			$updatedCount = 0;
			$errors = [];
			$snapshot = [];
			$touchedProductIds = [];

			foreach ($rows as &$row)
			{
				if (($row['status'] ?? '') !== self::RECEIPT_STATUS_READY || !boolval($row['apply_selected'] ?? false))
				{
					continue;
				}

				$stockId = $this->normalizeOptionalString($row['selected_stock_entry_id'] ?? null);
				if ($stockId === null)
				{
					$errors[] = [
						'line_number' => $row['line_number'] ?? null,
						'error' => 'selected_stock_entry_id missing for READY row',
					];
					continue;
				}

				$entry = $this->getDatabase()->stock()->where('stock_id = ?', $stockId)->fetch();
				$logRows = $this->loadBackfillableStockLogRowsByStockId($stockId);
				if ($entry === null && count($logRows) === 0)
				{
					$errors[] = [
						'line_number' => $row['line_number'] ?? null,
						'stock_id' => $stockId,
						'error' => 'stock entry history not found',
					];
					continue;
				}

				$productIdForTouch = null;
				if ($entry !== null)
				{
					$productIdForTouch = intval($entry->product_id);
					$snapshot[] = [
						'target_type' => 'stock',
						'stock_row_id' => strval($entry->stock_id),
						'product_id' => intval($entry->product_id),
						'old_price' => $entry->price === null ? null : strval($entry->price),
						'old_shopping_location_id' => $entry->shopping_location_id === null ? null : intval($entry->shopping_location_id),
					];
				}

				foreach ($logRows as $logRow)
				{
					if ($productIdForTouch === null)
					{
						$productIdForTouch = intval($logRow->product_id);
					}

					$snapshot[] = [
						'target_type' => 'stock_log',
						'stock_row_id' => $stockId,
						'stock_log_row_id' => intval($logRow->id),
						'product_id' => intval($logRow->product_id),
						'old_price' => $logRow->price === null ? null : strval($logRow->price),
						'old_shopping_location_id' => $logRow->shopping_location_id === null ? null : intval($logRow->shopping_location_id),
					];
				}

				$updateData = [];
				$proposedPrice = $row['proposed_price'] ?? null;
				$proposedStoreId = $this->normalizeOptionalInt($row['proposed_store_id'] ?? null);
				if ($proposedStoreId === null)
				{
					$proposedStoreId = $this->normalizeOptionalInt($row['matched_store_id'] ?? $defaultStoreId);
				}

				if ($proposedPrice !== null && $proposedPrice !== '')
				{
					$updateData['price'] = $proposedPrice;
				}
				if ($proposedStoreId !== null)
				{
					$updateData['shopping_location_id'] = $proposedStoreId;
				}

				if (count($updateData) === 0)
				{
					continue;
				}

				if ($entry !== null)
				{
					$this->getDatabase()->stock()->where('stock_id = ?', $stockId)->update($updateData);
				}

				foreach ($logRows as $logRow)
				{
					$this->getDatabase()->stock_log()->where('id = ?', intval($logRow->id))->update($updateData);
				}
				if ($productIdForTouch === null && array_key_exists('selected_product_id', $row) && is_numeric($row['selected_product_id']))
				{
					$productIdForTouch = intval($row['selected_product_id']);
				}
				if ($productIdForTouch !== null)
				{
					$touchedProductIds[] = $productIdForTouch;
				}
				$updatedCount++;
			}

			$this->refreshReceiptBackfillProductCaches($touchedProductIds);

			$reviewResult['staging']['rows'] = $rows;
			return $this->ApiResponse($response, [
				'staging' => $reviewResult['staging'],
				'summary' => $reviewResult['summary'],
				'updated_count' => $updatedCount,
				'errors' => $errors,
				'snapshot' => $snapshot,
			]);
		}
		catch (\Exception $ex)
		{
			return $this->GenericErrorResponse($response, $ex->getMessage());
		}
	}

	public function ReceiptBackfillGeneratePurchases(Request $request, Response $response, array $args)
	{
		User::checkPermission($request, User::PERMISSION_STOCK_PURCHASE);

		try
		{
			$requestBody = $request->getParsedBody();
			if (!is_array($requestBody))
			{
				throw new \Exception('Invalid request body');
			}
			if (!array_key_exists('staging', $requestBody) || !is_array($requestBody['staging']))
			{
				throw new \Exception('staging payload is required');
			}

			$daysWindow = null;
			if (array_key_exists('days_window', $requestBody) && is_numeric($requestBody['days_window']))
			{
				$daysWindow = intval($requestBody['days_window']);
			}

			$reviewResult = $this->reviewStaging($requestBody['staging'], $daysWindow);
			$rows = $reviewResult['staging']['rows'];
			$defaultStoreId = $this->normalizeOptionalInt($reviewResult['staging']['matched_store_id'] ?? null);

			$createdCount = 0;
			$errors = [];
			$snapshot = [];
			$touchedProductIds = [];

			foreach ($rows as &$row)
			{
				if (($row['status'] ?? '') !== self::RECEIPT_STATUS_READY_CREATE_PURCHASE || !boolval($row['apply_selected'] ?? false))
				{
					continue;
				}

				$lineNumber = $row['line_number'] ?? null;
				$productId = $this->normalizeOptionalInt($row['selected_product_id'] ?? null);
				$locationId = $this->normalizeOptionalInt($row['proposed_location_id'] ?? null);
				$shoppingLocationId = $this->normalizeOptionalInt($row['proposed_store_id'] ?? $row['matched_store_id'] ?? $defaultStoreId);
				$purchasedDate = IsIsoDate(strval($row['parsed_receipt_date'] ?? ''))
					? strval($row['parsed_receipt_date'])
					: (IsIsoDate(strval($reviewResult['staging']['receipt_date'] ?? '')) ? strval($reviewResult['staging']['receipt_date']) : date('Y-m-d'));
				$price = $row['proposed_price'] ?? null;

				$amount = 1.0;
				if (array_key_exists('parsed_quantity', $row) && is_numeric($row['parsed_quantity']) && floatval($row['parsed_quantity']) > 0)
				{
					$amount = floatval($row['parsed_quantity']);
				}

				if ($productId === null || $locationId === null)
				{
					$errors[] = [
						'line_number' => $lineNumber,
						'error' => 'missing required product/location/amount fields for purchase creation',
					];
					continue;
				}

				if (!is_numeric($price ?? null))
				{
					$errors[] = [
						'line_number' => $lineNumber,
						'error' => 'missing or invalid proposed_price for purchase creation',
					];
					continue;
				}

				$activeLocation = $this->getDatabase()->locations()->where('id = ?', $locationId)->where('active = 1')->fetch();
				if ($activeLocation === null)
				{
					$errors[] = [
						'line_number' => $lineNumber,
						'error' => 'proposed location is not active or does not exist',
					];
					continue;
				}

				try
				{
					$note = 'Receipt-generated purchase entry';
					if (array_key_exists('line_number', $row) && is_numeric($row['line_number']))
					{
						$note .= ' (line ' . intval($row['line_number']) . ')';
					}

					$transactionId = $this->getStockService()->AddProduct(
						$productId,
						$amount,
						'2999-12-31',
						StockService::TRANSACTION_TYPE_PURCHASE,
						$purchasedDate,
						$price,
						$locationId,
						$shoppingLocationId,
						$unusedTransactionId,
						0,
						false,
						$note
					);

					$createdLogRow = $this->getDatabase()->stock_log()
						->where('transaction_id = ?', intval($transactionId))
						->where('transaction_type = ?', StockService::TRANSACTION_TYPE_PURCHASE)
						->orderBy('id', 'DESC')
						->fetch();

					$snapshot[] = [
						'line_number' => $lineNumber,
						'transaction_id' => intval($transactionId),
						'stock_id' => $createdLogRow === null ? null : strval($createdLogRow->stock_id),
						'stock_log_row_id' => $createdLogRow === null ? null : intval($createdLogRow->id),
						'product_id' => $productId,
						'amount' => strval($amount),
						'purchased_date' => $purchasedDate,
						'price' => strval($price),
						'location_id' => $locationId,
						'shopping_location_id' => $shoppingLocationId,
					];

					$touchedProductIds[] = $productId;
					$row['apply_selected'] = false;
					$row['generated_purchase_transaction_id'] = intval($transactionId);
					$createdCount++;
				}
				catch (\Exception $rowEx)
				{
					$errors[] = [
						'line_number' => $lineNumber,
						'error' => $rowEx->getMessage(),
					];
				}
			}

			$this->refreshReceiptBackfillProductCaches($touchedProductIds);
			$reviewResult['staging']['rows'] = $rows;

			return $this->ApiResponse($response, [
				'staging' => $reviewResult['staging'],
				'summary' => $reviewResult['summary'],
				'created_count' => $createdCount,
				'errors' => $errors,
				'snapshot' => $snapshot,
			]);
		}
		catch (\Exception $ex)
		{
			return $this->GenericErrorResponse($response, $ex->getMessage());
		}
	}

	public function AddMissingProductsToShoppingList(Request $request, Response $response, array $args)
	{
		User::checkPermission($request, User::PERMISSION_SHOPPINGLIST_ITEMS_ADD);

		try
		{
			$requestBody = $this->GetParsedAndFilteredRequestBody($request);

			$listId = 1;

			if (array_key_exists('list_id', $requestBody) && !empty($requestBody['list_id']) && is_numeric($requestBody['list_id']))
			{
				$listId = intval($requestBody['list_id']);
			}

			$this->getStockService()->AddMissingProductsToShoppingList($listId);
			return $this->EmptyApiResponse($response);
		}
		catch (\Exception $ex)
		{
			return $this->GenericErrorResponse($response, $ex->getMessage());
		}
	}

	public function AddOverdueProductsToShoppingList(Request $request, Response $response, array $args)
	{
		User::checkPermission($request, User::PERMISSION_SHOPPINGLIST_ITEMS_ADD);

		try
		{
			$requestBody = $this->GetParsedAndFilteredRequestBody($request);

			$listId = 1;

			if (array_key_exists('list_id', $requestBody) && !empty($requestBody['list_id']) && is_numeric($requestBody['list_id']))
			{
				$listId = intval($requestBody['list_id']);
			}

			$this->getStockService()->AddOverdueProductsToShoppingList($listId);
			return $this->EmptyApiResponse($response);
		}
		catch (\Exception $ex)
		{
			return $this->GenericErrorResponse($response, $ex->getMessage());
		}
	}

	public function AddExpiredProductsToShoppingList(Request $request, Response $response, array $args)
	{
		User::checkPermission($request, User::PERMISSION_SHOPPINGLIST_ITEMS_ADD);

		try
		{
			$requestBody = $this->GetParsedAndFilteredRequestBody($request);

			$listId = 1;

			if (array_key_exists('list_id', $requestBody) && !empty($requestBody['list_id']) && is_numeric($requestBody['list_id']))
			{
				$listId = intval($requestBody['list_id']);
			}

			$this->getStockService()->AddExpiredProductsToShoppingList($listId);
			return $this->EmptyApiResponse($response);
		}
		catch (\Exception $ex)
		{
			return $this->GenericErrorResponse($response, $ex->getMessage());
		}
	}

	public function AddProduct(Request $request, Response $response, array $args)
	{
		User::checkPermission($request, User::PERMISSION_STOCK_PURCHASE);

		$requestBody = $this->GetParsedAndFilteredRequestBody($request);

		try
		{
			if ($requestBody === null)
			{
				throw new \Exception('Request body could not be parsed (probably invalid JSON format or missing/wrong Content-Type header)');
			}

			if (!array_key_exists('amount', $requestBody))
			{
				throw new \Exception('An amount is required');
			}

			$bestBeforeDate = null;
			if (array_key_exists('best_before_date', $requestBody) && IsIsoDate($requestBody['best_before_date']))
			{
				$bestBeforeDate = $requestBody['best_before_date'];
			}

			$purchasedDate = date('Y-m-d');
			if (array_key_exists('purchased_date', $requestBody) && IsIsoDate($requestBody['purchased_date']))
			{
				$purchasedDate = $requestBody['purchased_date'];
			}

			$price = null;
			if (array_key_exists('price', $requestBody) && is_numeric($requestBody['price']))
			{
				$price = $requestBody['price'];
			}

			$locationId = null;
			if (array_key_exists('location_id', $requestBody) && is_numeric($requestBody['location_id']))
			{
				$locationId = $requestBody['location_id'];
			}

			$shoppingLocationId = null;
			if (array_key_exists('shopping_location_id', $requestBody) && is_numeric($requestBody['shopping_location_id']))
			{
				$shoppingLocationId = $requestBody['shopping_location_id'];
			}

			$transactionType = StockService::TRANSACTION_TYPE_PURCHASE;
			if (array_key_exists('transaction_type', $requestBody) && !empty($requestBody['transaction_type']))
			{
				$transactionType = $requestBody['transaction_type'];
			}

			$stockLabelType = 0;
			if (array_key_exists('stock_label_type', $requestBody) && is_numeric($requestBody['stock_label_type']))
			{
				$stockLabelType = intval($requestBody['stock_label_type']);
			}

			$note = null;
			if (array_key_exists('note', $requestBody))
			{
				$note = $requestBody['note'];
			}

			$transactionId = $this->getStockService()->AddProduct($args['productId'], $requestBody['amount'], $bestBeforeDate, $transactionType, $purchasedDate, $price, $locationId, $shoppingLocationId, $unusedTransactionId, $stockLabelType, false, $note);

			$args['transactionId'] = $transactionId;
			return $this->StockTransactions($request, $response, $args);
		}
		catch (\Exception $ex)
		{
			return $this->GenericErrorResponse($response, $ex->getMessage());
		}
	}

	public function AddProductByBarcode(Request $request, Response $response, array $args)
	{
		try
		{
			$args['productId'] = $this->getStockService()->GetProductIdFromBarcode($args['barcode']);
			return $this->AddProduct($request, $response, $args);
		}
		catch (\Exception $ex)
		{
			return $this->GenericErrorResponse($response, $ex->getMessage());
		}
	}

	public function AddProductToShoppingList(Request $request, Response $response, array $args)
	{
		User::checkPermission($request, User::PERMISSION_SHOPPINGLIST_ITEMS_ADD);

		try
		{
			$requestBody = $this->GetParsedAndFilteredRequestBody($request);

			$listId = 1;
			$amount = 1;
			$quId = -1;
			$productId = null;
			$note = null;

			if (array_key_exists('list_id', $requestBody) && !empty($requestBody['list_id']) && is_numeric($requestBody['list_id']))
			{
				$listId = intval($requestBody['list_id']);
			}

			if (array_key_exists('product_amount', $requestBody) && !empty($requestBody['product_amount']) && is_numeric($requestBody['product_amount']))
			{
				$amount = intval($requestBody['product_amount']);
			}

			if (array_key_exists('product_id', $requestBody) && !empty($requestBody['product_id']) && is_numeric($requestBody['product_id']))
			{
				$productId = intval($requestBody['product_id']);
			}

			if (array_key_exists('note', $requestBody) && !empty($requestBody['note']))
			{
				$note = $requestBody['note'];
			}

			if (array_key_exists('qu_id', $requestBody) && !empty($requestBody['qu_id']))
			{
				$quId = $requestBody['qu_id'];
			}

			if ($productId == null)
			{
				throw new \Exception('No product id was supplied');
			}

			$this->getStockService()->AddProductToShoppingList($productId, $amount, $quId, $note, $listId);
			return $this->EmptyApiResponse($response);
		}
		catch (\Exception $ex)
		{
			return $this->GenericErrorResponse($response, $ex->getMessage());
		}
	}

	public function ClearShoppingList(Request $request, Response $response, array $args)
	{
		User::checkPermission($request, User::PERMISSION_SHOPPINGLIST_ITEMS_DELETE);

		try
		{
			$requestBody = $this->GetParsedAndFilteredRequestBody($request);

			$listId = 1;
			if (array_key_exists('list_id', $requestBody) && !empty($requestBody['list_id']) && is_numeric($requestBody['list_id']))
			{
				$listId = intval($requestBody['list_id']);
			}

			$doneOnly = false;
			if (array_key_exists('done_only', $requestBody) && filter_var($requestBody['done_only'], FILTER_VALIDATE_BOOLEAN) !== false)
			{
				$doneOnly = boolval($requestBody['done_only']);
			}

			$this->getStockService()->ClearShoppingList($listId, $doneOnly);
			return $this->EmptyApiResponse($response);
		}
		catch (\Exception $ex)
		{
			return $this->GenericErrorResponse($response, $ex->getMessage());
		}
	}

	public function ConsumeProduct(Request $request, Response $response, array $args)
	{
		User::checkPermission($request, User::PERMISSION_STOCK_CONSUME);

		$requestBody = $this->GetParsedAndFilteredRequestBody($request);
		if ($requestBody === null)
		{
			$localizedRequestBody = $this->TryParseConsumeRequestBodyWithLocalizedAmount($request);
			if ($localizedRequestBody !== null)
			{
				$requestBody = $localizedRequestBody;
			}
		}

		try
		{
			if ($requestBody === null)
			{
				throw new \Exception('Request body could not be parsed (probably invalid JSON format or missing/wrong Content-Type header)');
			}

			if (!array_key_exists('amount', $requestBody))
			{
				throw new \Exception('An amount is required');
			}

			$spoiled = false;
			if (array_key_exists('spoiled', $requestBody))
			{
				$spoiled = $requestBody['spoiled'];
			}

			$transactionType = StockService::TRANSACTION_TYPE_CONSUME;
			if (array_key_exists('transaction_type', $requestBody) && !empty($requestBody['transactiontype']))
			{
				$transactionType = $requestBody['transactiontype'];
			}

			$specificStockEntryId = 'default';
			if (array_key_exists('stock_entry_id', $requestBody) && !empty($requestBody['stock_entry_id']))
			{
				$specificStockEntryId = $requestBody['stock_entry_id'];
			}

			$locationId = null;
			if (array_key_exists('location_id', $requestBody) && !empty($requestBody['location_id']) && is_numeric($requestBody['location_id']))
			{
				$locationId = $requestBody['location_id'];
			}

			$recipeId = null;
			if (array_key_exists('recipe_id', $requestBody) && is_numeric($requestBody['recipe_id']))
			{
				$recipeId = $requestBody['recipe_id'];
			}

			$consumeExact = false;
			if (array_key_exists('exact_amount', $requestBody))
			{
				$consumeExact = $requestBody['exact_amount'];
			}

			$allowSubproductSubstitution = false;
			if (array_key_exists('allow_subproduct_substitution', $requestBody))
			{
				$allowSubproductSubstitution = $requestBody['allow_subproduct_substitution'];
			}

			$transactionId = null;
			$transactionId = $this->getStockService()->ConsumeProduct($args['productId'], $requestBody['amount'], $spoiled, $transactionType, $specificStockEntryId, $recipeId, $locationId, $transactionId, $allowSubproductSubstitution, $consumeExact);
			$args['transactionId'] = $transactionId;
			return $this->StockTransactions($request, $response, $args);
		}
		catch (\Exception $ex)
		{
			return $this->GenericErrorResponse($response, $ex->getMessage());
		}
	}

	public function ConsumeProductByBarcode(Request $request, Response $response, array $args)
	{
		try
		{
			$args['productId'] = $this->getStockService()->GetProductIdFromBarcode($args['barcode']);

			if (Grocycode::Validate($args['barcode']))
			{
				$gc = new Grocycode($args['barcode']);
				if ($gc->GetExtraData())
				{
					$requestBody = $request->getParsedBody();
					$requestBody['stock_entry_id'] = $gc->GetExtraData()[0];
					$request = $request->withParsedBody($requestBody);
				}
			}

			return $this->ConsumeProduct($request, $response, $args);
		}
		catch (\Exception $ex)
		{
			return $this->GenericErrorResponse($response, $ex->getMessage());
		}
	}

	public function CurrentStock(Request $request, Response $response, array $args)
	{
		return $this->ApiResponse($response, $this->getStockService()->GetCurrentStock());
	}

	public function CurrentVolatileStock(Request $request, Response $response, array $args)
	{
		$nextXDays = 5;

		if (isset($request->getQueryParams()['due_soon_days']) && !empty($request->getQueryParams()['due_soon_days']) && is_numeric($request->getQueryParams()['due_soon_days']))
		{
			$nextXDays = $request->getQueryParams()['due_soon_days'];
		}

		$dueProducts = $this->getStockService()->GetDueProducts($nextXDays, true);
		$overdueProducts = $this->getStockService()->GetDueProducts(-1);
		$expiredProducts = $this->getStockService()->GetExpiredProducts();
		$missingProducts = $this->getStockService()->GetMissingProducts();
		return $this->ApiResponse($response, [
			'due_products' => $dueProducts,
			'overdue_products' => $overdueProducts,
			'expired_products' => $expiredProducts,
			'missing_products' => $missingProducts
		]);
	}

	public function EditStockEntry(Request $request, Response $response, array $args)
	{
		User::checkPermission($request, User::PERMISSION_STOCK_EDIT);

		$requestBody = $this->GetParsedAndFilteredRequestBody($request);

		try
		{
			if ($requestBody === null)
			{
				throw new \Exception('Request body could not be parsed (probably invalid JSON format or missing/wrong Content-Type header)');
			}

			if (!array_key_exists('amount', $requestBody))
			{
				throw new \Exception('An amount is required');
			}

			$bestBeforeDate = null;
			if (array_key_exists('best_before_date', $requestBody) && IsIsoDate($requestBody['best_before_date']))
			{
				$bestBeforeDate = $requestBody['best_before_date'];
			}

			$price = null;
			if (array_key_exists('price', $requestBody) && is_numeric($requestBody['price']))
			{
				$price = $requestBody['price'];
			}

			$locationId = null;
			if (array_key_exists('location_id', $requestBody) && is_numeric($requestBody['location_id']))
			{
				$locationId = $requestBody['location_id'];
			}

			$shoppingLocationId = null;
			if (array_key_exists('shopping_location_id', $requestBody) && is_numeric($requestBody['shopping_location_id']))
			{
				$shoppingLocationId = $requestBody['shopping_location_id'];
			}

			$note = null;
			if (array_key_exists('note', $requestBody))
			{
				$note = $requestBody['note'];
			}

			$transactionId = $this->getStockService()->EditStockEntry($args['entryId'], $requestBody['amount'], $bestBeforeDate, $locationId, $shoppingLocationId, $price, $requestBody['open'], $requestBody['purchased_date'], $note);
			$args['transactionId'] = $transactionId;
			return $this->StockTransactions($request, $response, $args);
		}
		catch (\Exception $ex)
		{
			return $this->GenericErrorResponse($response, $ex->getMessage());
		}
	}

	public function ExternalBarcodeLookup(Request $request, Response $response, array $args)
	{
		User::checkPermission($request, User::PERMISSION_MASTER_DATA_EDIT);

		try
		{
			$addFoundProduct = false;
			if (isset($request->getQueryParams()['add']) && ($request->getQueryParams()['add'] === 'true' || $request->getQueryParams()['add'] === 1))
			{
				$addFoundProduct = true;
			}

			return $this->ApiResponse($response, $this->getStockService()->ExternalBarcodeLookup($args['barcode'], $addFoundProduct));
		}
		catch (\Exception $ex)
		{
			return $this->GenericErrorResponse($response, $ex->getMessage());
		}
	}

	public function InventoryProduct(Request $request, Response $response, array $args)
	{
		User::checkPermission($request, User::PERMISSION_STOCK_INVENTORY);

		$requestBody = $this->GetParsedAndFilteredRequestBody($request);

		try
		{
			if ($requestBody === null)
			{
				throw new \Exception('Request body could not be parsed (probably invalid JSON format or missing/wrong Content-Type header)');
			}

			if (!array_key_exists('new_amount', $requestBody))
			{
				throw new \Exception('An new amount is required');
			}

			$bestBeforeDate = null;
			if (array_key_exists('best_before_date', $requestBody) && IsIsoDate($requestBody['best_before_date']))
			{
				$bestBeforeDate = $requestBody['best_before_date'];
			}

			$purchasedDate = null;
			if (array_key_exists('purchased_date', $requestBody) && IsIsoDate($requestBody['purchased_date']))
			{
				$purchasedDate = $requestBody['purchased_date'];
			}

			$locationId = null;
			if (array_key_exists('location_id', $requestBody) && is_numeric($requestBody['location_id']))
			{
				$locationId = $requestBody['location_id'];
			}

			$price = null;
			if (array_key_exists('price', $requestBody) && is_numeric($requestBody['price']))
			{
				$price = $requestBody['price'];
			}

			$shoppingLocationId = null;
			if (array_key_exists('shopping_location_id', $requestBody) && is_numeric($requestBody['shopping_location_id']))
			{
				$shoppingLocationId = $requestBody['shopping_location_id'];
			}

			$stockLabelType = 0;
			if (array_key_exists('stock_label_type', $requestBody) && is_numeric($requestBody['stock_label_type']))
			{
				$stockLabelType = intval($requestBody['stock_label_type']);
			}

			$note = null;
			if (array_key_exists('note', $requestBody))
			{
				$note = $requestBody['note'];
			}

			$transactionId = $this->getStockService()->InventoryProduct($args['productId'], $requestBody['new_amount'], $bestBeforeDate, $locationId, $price, $shoppingLocationId, $purchasedDate, $stockLabelType, $note);
			$args['transactionId'] = $transactionId;
			return $this->StockTransactions($request, $response, $args);
		}
		catch (\Exception $ex)
		{
			return $this->GenericErrorResponse($response, $ex->getMessage());
		}
	}

	public function InventoryProductByBarcode(Request $request, Response $response, array $args)
	{
		try
		{
			$args['productId'] = $this->getStockService()->GetProductIdFromBarcode($args['barcode']);
			return $this->InventoryProduct($request, $response, $args);
		}
		catch (\Exception $ex)
		{
			return $this->GenericErrorResponse($response, $ex->getMessage());
		}
	}

	public function OpenProduct(Request $request, Response $response, array $args)
	{
		User::checkPermission($request, User::PERMISSION_STOCK_OPEN);

		$requestBody = $this->GetParsedAndFilteredRequestBody($request);

		try
		{
			if ($requestBody === null)
			{
				throw new \Exception('Request body could not be parsed (probably invalid JSON format or missing/wrong Content-Type header)');
			}

			if (!array_key_exists('amount', $requestBody))
			{
				throw new \Exception('An amount is required');
			}

			$specificStockEntryId = 'default';
			if (array_key_exists('stock_entry_id', $requestBody) && !empty($requestBody['stock_entry_id']))
			{
				$specificStockEntryId = $requestBody['stock_entry_id'];
			}

			$allowSubproductSubstitution = false;
			if (array_key_exists('allow_subproduct_substitution', $requestBody))
			{
				$allowSubproductSubstitution = $requestBody['allow_subproduct_substitution'];
			}

			$transactionId = null;
			$transactionId = $this->getStockService()->OpenProduct($args['productId'], $requestBody['amount'], $specificStockEntryId, $transactionId, $allowSubproductSubstitution);
			$args['transactionId'] = $transactionId;
			return $this->StockTransactions($request, $response, $args);
		}
		catch (\Exception $ex)
		{
			return $this->GenericErrorResponse($response, $ex->getMessage());
		}
	}

	public function OpenProductByBarcode(Request $request, Response $response, array $args)
	{
		try
		{
			$args['productId'] = $this->getStockService()->GetProductIdFromBarcode($args['barcode']);

			if (Grocycode::Validate($args['barcode']))
			{
				$gc = new Grocycode($args['barcode']);
				if ($gc->GetExtraData())
				{
					$requestBody = $request->getParsedBody();
					$requestBody['stock_entry_id'] = $gc->GetExtraData()[0];
					$request = $request->withParsedBody($requestBody);
				}
			}

			return $this->OpenProduct($request, $response, $args);
		}
		catch (\Exception $ex)
		{
			return $this->GenericErrorResponse($response, $ex->getMessage());
		}
	}

	public function ProductDetails(Request $request, Response $response, array $args)
	{
		try
		{
			return $this->ApiResponse($response, $this->getStockService()->GetProductDetails($args['productId']));
		}
		catch (\Exception $ex)
		{
			return $this->GenericErrorResponse($response, $ex->getMessage());
		}
	}

	public function ProductDetailsByBarcode(Request $request, Response $response, array $args)
	{
		try
		{
			$productId = $this->getStockService()->GetProductIdFromBarcode($args['barcode']);
			return $this->ApiResponse($response, $this->getStockService()->GetProductDetails($productId));
		}
		catch (\Exception $ex)
		{
			return $this->GenericErrorResponse($response, $ex->getMessage());
		}
	}

	public function ProductPriceHistory(Request $request, Response $response, array $args)
	{
		try
		{
			return $this->ApiResponse($response, $this->getStockService()->GetProductPriceHistory($args['productId']));
		}
		catch (\Exception $ex)
		{
			return $this->GenericErrorResponse($response, $ex->getMessage());
		}
	}

	public function ProductStockEntries(Request $request, Response $response, array $args)
	{
		$allowSubproductSubstitution = false;
		if (isset($request->getQueryParams()['include_sub_products']) && filter_var($request->getQueryParams()['include_sub_products'], FILTER_VALIDATE_BOOLEAN) !== false)
		{
			$allowSubproductSubstitution = true;
		}

		return $this->FilteredApiResponse($response, $this->getStockService()->GetProductStockEntries($args['productId'], false, $allowSubproductSubstitution), $request->getQueryParams());
	}

	public function LocationStockEntries(Request $request, Response $response, array $args)
	{
		return $this->FilteredApiResponse($response, $this->getStockService()->GetLocationStockEntries($args['locationId']), $request->getQueryParams());
	}

	public function ProductStockLocations(Request $request, Response $response, array $args)
	{
		$allowSubproductSubstitution = false;
		if (isset($request->getQueryParams()['include_sub_products']) && filter_var($request->getQueryParams()['include_sub_products'], FILTER_VALIDATE_BOOLEAN) !== false)
		{
			$allowSubproductSubstitution = true;
		}

		return $this->FilteredApiResponse($response, $this->getStockService()->GetProductStockLocations($args['productId'], $allowSubproductSubstitution), $request->getQueryParams());
	}

	public function ProductPrintLabel(Request $request, Response $response, array $args)
	{
		try
		{
			$productDetails = (object)$this->getStockService()->GetProductDetails($args['productId']);

			$webhookData = array_merge([
				'product' => $productDetails->product->name,
				'product_display_name' => $productDetails->product_display_name,
				'grocycode' => (string)(new Grocycode(Grocycode::PRODUCT, $productDetails->product->id)),
				'details' => $productDetails,
			], GROCY_LABEL_PRINTER_PARAMS);

			if (GROCY_LABEL_PRINTER_RUN_SERVER)
			{
				(new WebhookRunner())->run(GROCY_LABEL_PRINTER_WEBHOOK, $webhookData, GROCY_LABEL_PRINTER_HOOK_JSON);
			}

			return $this->ApiResponse($response, $webhookData);
		}
		catch (\Exception $ex)
		{
			return $this->GenericErrorResponse($response, $ex->getMessage());
		}
	}

	public function StockEntryPrintLabel(Request $request, Response $response, array $args)
	{
		try
		{
			$stockEntry = $this->getDatabase()->stock()->where('id', $args['entryId'])->fetch();
			$productDetails = (object)$this->getStockService()->GetProductDetails($stockEntry->product_id);

			$webhookData = array_merge([
				'product' => $productDetails->product->name,
				'product_display_name' => $productDetails->product_display_name,
				'grocycode' => (string)(new Grocycode(Grocycode::PRODUCT, $stockEntry->product_id, [$stockEntry->stock_id])),
				'details' => $productDetails,
				'stock_entry' => $stockEntry,
			], GROCY_LABEL_PRINTER_PARAMS);

			if (GROCY_FEATURE_FLAG_STOCK_BEST_BEFORE_DATE_TRACKING)
			{
				$webhookData['due_date'] = $this->getLocalizationService()->__t('DD') . ': ' . $stockEntry->best_before_date;
			}

			if (GROCY_LABEL_PRINTER_RUN_SERVER)
			{
				(new WebhookRunner())->run(GROCY_LABEL_PRINTER_WEBHOOK, $webhookData, GROCY_LABEL_PRINTER_HOOK_JSON);
			}

			return $this->ApiResponse($response, $webhookData);
		}
		catch (\Exception $ex)
		{
			return $this->GenericErrorResponse($response, $ex->getMessage());
		}
	}

	public function RemoveProductFromShoppingList(Request $request, Response $response, array $args)
	{
		User::checkPermission($request, User::PERMISSION_SHOPPINGLIST_ITEMS_DELETE);

		try
		{
			$requestBody = $this->GetParsedAndFilteredRequestBody($request);

			$listId = 1;
			$amount = 1;
			$productId = null;

			if (array_key_exists('list_id', $requestBody) && !empty($requestBody['list_id']) && is_numeric($requestBody['list_id']))
			{
				$listId = intval($requestBody['list_id']);
			}

			if (array_key_exists('product_amount', $requestBody) && !empty($requestBody['product_amount']) && is_numeric($requestBody['product_amount']))
			{
				$amount = intval($requestBody['product_amount']);
			}

			if (array_key_exists('product_id', $requestBody) && !empty($requestBody['product_id']) && is_numeric($requestBody['product_id']))
			{
				$productId = intval($requestBody['product_id']);
			}

			if ($productId == null)
			{
				throw new \Exception('No product id was supplied');
			}

			$this->getStockService()->RemoveProductFromShoppingList($productId, $amount, $listId);
			return $this->EmptyApiResponse($response);
		}
		catch (\Exception $ex)
		{
			return $this->GenericErrorResponse($response, $ex->getMessage());
		}
	}

	public function StockBooking(Request $request, Response $response, array $args)
	{
		try
		{
			$stockLogRow = $this->getDatabase()->stock_log($args['bookingId']);

			if ($stockLogRow === null)
			{
				throw new \Exception('Stock booking does not exist');
			}

			return $this->ApiResponse($response, $stockLogRow);
		}
		catch (\Exception $ex)
		{
			return $this->GenericErrorResponse($response, $ex->getMessage());
		}
	}

	public function StockEntry(Request $request, Response $response, array $args)
	{
		return $this->ApiResponse($response, $this->getStockService()->GetStockEntry($args['entryId']));
	}

	public function StockTransactions(Request $request, Response $response, array $args)
	{
		try
		{
			$transactionRows = $this->getDatabase()->stock_log()->where('transaction_id = :1', $args['transactionId'])->fetchAll();
			if (count($transactionRows) === 0)
			{
				throw new \Exception('No transaction was found by the given transaction id');
			}

			return $this->ApiResponse($response, $transactionRows);
		}
		catch (\Exception $ex)
		{
			return $this->GenericErrorResponse($response, $ex->getMessage());
		}
	}

	public function TransferProduct(Request $request, Response $response, array $args)
	{
		User::checkPermission($request, User::PERMISSION_STOCK_TRANSFER);

		$requestBody = $this->GetParsedAndFilteredRequestBody($request);

		try
		{
			if ($requestBody === null)
			{
				throw new \Exception('Request body could not be parsed (probably invalid JSON format or missing/wrong Content-Type header)');
			}

			if (!array_key_exists('amount', $requestBody))
			{
				throw new \Exception('An amount is required');
			}

			if (!array_key_exists('location_id_from', $requestBody))
			{
				throw new \Exception('A transfer from location is required');
			}

			if (!array_key_exists('location_id_to', $requestBody))
			{
				throw new \Exception('A transfer to location is required');
			}

			$specificStockEntryId = 'default';

			if (array_key_exists('stock_entry_id', $requestBody) && !empty($requestBody['stock_entry_id']))
			{
				$specificStockEntryId = $requestBody['stock_entry_id'];
			}

			$transactionId = $this->getStockService()->TransferProduct($args['productId'], $requestBody['amount'], $requestBody['location_id_from'], $requestBody['location_id_to'], $specificStockEntryId);
			$args['transactionId'] = $transactionId;
			return $this->StockTransactions($request, $response, $args);
		}
		catch (\Exception $ex)
		{
			return $this->GenericErrorResponse($response, $ex->getMessage());
		}
	}

	public function TransferProductByBarcode(Request $request, Response $response, array $args)
	{
		try
		{
			$args['productId'] = $this->getStockService()->GetProductIdFromBarcode($args['barcode']);

			if (Grocycode::Validate($args['barcode']))
			{
				$gc = new Grocycode($args['barcode']);
				if ($gc->GetExtraData())
				{
					$requestBody = $request->getParsedBody();
					$requestBody['stock_entry_id'] = $gc->GetExtraData()[0];
					$request = $request->withParsedBody($requestBody);
				}
			}

			return $this->TransferProduct($request, $response, $args);
		}
		catch (\Exception $ex)
		{
			return $this->GenericErrorResponse($response, $ex->getMessage());
		}
	}

	public function UndoBooking(Request $request, Response $response, array $args)
	{
		User::checkPermission($request, User::PERMISSION_STOCK_EDIT);

		try
		{
			$this->ApiResponse($response, $this->getStockService()->UndoBooking($args['bookingId']));
			return $this->EmptyApiResponse($response);
		}
		catch (\Exception $ex)
		{
			return $this->GenericErrorResponse($response, $ex->getMessage());
		}
	}

	public function UndoTransaction(Request $request, Response $response, array $args)
	{
		User::checkPermission($request, User::PERMISSION_STOCK_EDIT);

		try
		{
			$this->ApiResponse($response, $this->getStockService()->UndoTransaction($args['transactionId']));
			return $this->EmptyApiResponse($response);
		}
		catch (\Exception $ex)
		{
			return $this->GenericErrorResponse($response, $ex->getMessage());
		}
	}

	public function MergeProducts(Request $request, Response $response, array $args)
	{
		User::checkPermission($request, User::PERMISSION_STOCK_EDIT);

		try
		{
			if (filter_var($args['productIdToKeep'], FILTER_VALIDATE_INT) === false || filter_var($args['productIdToRemove'], FILTER_VALIDATE_INT) === false)
			{
				throw new \Exception('Provided {productIdToKeep} or {productIdToRemove} is not a valid integer');
			}

			$this->ApiResponse($response, $this->getStockService()->MergeProducts($args['productIdToKeep'], $args['productIdToRemove']));
			return $this->EmptyApiResponse($response);
		}
		catch (\Exception $ex)
		{
			return $this->GenericErrorResponse($response, $ex->getMessage());
		}
	}
}
