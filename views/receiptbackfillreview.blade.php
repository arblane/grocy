@extends('layout.default')

@section('title', $__t('Receipt review'))

@push('pageStyles')
<style>
	.receipt-review-table th,
	.receipt-review-table td {
		vertical-align: top;
	}

	.receipt-review-table code {
		white-space: pre-wrap;
		word-break: break-word;
	}

	.receipt-review-badge {
		font-size: 0.75rem;
	}

	.receipt-review-json {
		min-height: 14rem;
		font-family: var(--font-family-monospace, monospace);
	}

	.receipt-review-summary dt {
		font-weight: 600;
	}

	.receipt-review-summary dd {
		margin-bottom: 0.35rem;
	}

	.receipt-review-toolbar {
		margin-bottom: 0.25rem;
	}

	.receipt-review-actionbar {
		padding: 0.35rem 0;
		margin-bottom: 0.35rem;
		background: var(--body-bg, #fff);
		border-bottom: 1px solid #d6d6d6;
	}

	.receipt-review-actionbar-fixed {
		position: fixed;
		top: @if($embedded) 0px @else 54px @endif;
		z-index: 1030;
	}

	.receipt-review-loader-toggle {
		text-align: left;
		text-decoration: none;
	}
</style>
@endpush

@push('pageScripts')
<script src="https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/pdf.min.js"></script>
@endpush

@section('content')
<div class="row receipt-review-toolbar">
	<div class="col">
		<div class="title-related-links">
			<h2 class="title">@yield('title')</h2>
		</div>
	</div>
</div>

<div id="receipt-review-actionbar-placeholder"></div>

<div id="receipt-review-actionbar" class="receipt-review-actionbar">
	<div class="title-related-links">
		<div class="float-right @if($embedded) pr-5 @endif">
			<button class="btn btn-outline-dark d-md-none mt-2 order-1 order-md-3"
				type="button"
				data-toggle="collapse"
				data-target="#receipt-review-related-links">
				<i class="fa-solid fa-ellipsis-v"></i>
			</button>
		</div>
		<div class="related-links collapse d-md-flex order-2 width-xs-sm-100"
			id="receipt-review-related-links">
			<button id="parse-uploaded-pdf-button"
				class="btn btn-outline-primary responsive-button m-1 mt-md-0 mb-md-0 float-right"
				type="button">
				{{ $__t('Parse uploaded PDF') }}
			</button>
			<button id="load-pasted-staging-button"
				class="btn btn-primary responsive-button m-1 mt-md-0 mb-md-0 float-right"
				type="button">
				{{ $__t('Load pasted staging JSON') }}
			</button>
			<button id="review-on-server-button"
				class="btn btn-outline-primary responsive-button m-1 mt-md-0 mb-md-0 float-right"
				type="button"
				disabled>
				{{ $__t('Re-evaluate on server') }}
			</button>
			<button id="apply-on-server-button"
				class="btn btn-success responsive-button m-1 mt-md-0 mb-md-0 float-right"
				type="button"
				disabled>
				{{ $__t('Apply selected on server') }}
			</button>
			<button id="generate-purchases-on-server-button"
				class="btn btn-outline-success responsive-button m-1 mt-md-0 mb-md-0 float-right"
				type="button"
				disabled>
				{{ $__t('Generate purchase entries for selected products') }}
			</button>
			<button id="download-staging-json-button"
				class="btn btn-outline-secondary responsive-button m-1 mt-md-0 mb-md-0 float-right"
				type="button"
				disabled>
				{{ $__t('Download updated JSON') }}
			</button>
			<button id="copy-staging-json-button"
				class="btn btn-outline-secondary responsive-button m-1 mt-md-0 mb-md-0 float-right"
				type="button"
				disabled>
				{{ $__t('Copy JSON') }}
			</button>
		</div>
	</div>
</div>

<hr class="my-2">

<div class="alert alert-info">
	{{ $__t('Load the staging JSON from the CLI preview command, select product and stock-entry overrides, then use "Re-evaluate on server" to refresh statuses. Use "Apply selected on server" for READY rows (price/store backfill), and "Generate purchase entries for selected products" for READY_CREATE_PURCHASE rows.') }}
</div>

<div class="card mb-3">
	<div class="card-header p-0">
		<button class="btn btn-link w-100 receipt-review-loader-toggle px-3 py-2"
			type="button"
			data-toggle="collapse"
			data-target="#receipt-review-loader-panel"
			aria-expanded="true"
			aria-controls="receipt-review-loader-panel">
			{{ $__t('Load staging JSON and staging summary') }}
			<i class="fa-solid fa-chevron-up float-right mt-1"></i>
		</button>
	</div>
	<div id="receipt-review-loader-panel" class="collapse show">
		<div class="card-body">
			<div class="row">
				<div class="col-12 col-xl-5 mb-3 mb-xl-0">
					<div class="form-group">
						<label for="receipt-pdf-file">{{ $__t('Receipt PDF') }}</label>
						<input id="receipt-pdf-file"
							class="form-control-file"
							type="file"
							accept="application/pdf,.pdf">
						<small class="form-text text-muted">{{ $__t('Upload a PDF and click "Parse uploaded PDF" to generate staging rows directly.') }}</small>
					</div>
					<div class="form-group">
						<label for="staging-json-file">{{ $__t('JSON file') }}</label>
						<input id="staging-json-file"
							class="form-control-file"
							type="file"
							accept="application/json,.json">
					</div>
					<div class="form-group mb-0">
						<label for="staging-json-input">{{ $__t('Or paste staging JSON') }}</label>
						<textarea id="staging-json-input"
							class="form-control receipt-review-json"
							spellcheck="false"
							placeholder="{ &quot;rows&quot;: [ ... ] }"></textarea>
					</div>
				</div>
				<div class="col-12 col-xl-7">
					<dl class="row receipt-review-summary mb-0">
						<dt class="col-sm-4">{{ $__t('Store') }}</dt>
						<dd id="summary-store" class="col-sm-8 text-muted">{{ $__t('No staging JSON loaded') }}</dd>
						<dt class="col-sm-4">{{ $__t('Receipt date') }}</dt>
						<dd id="summary-date" class="col-sm-8 text-muted">-</dd>
						<dt class="col-sm-4">{{ $__t('Rows') }}</dt>
						<dd id="summary-rows" class="col-sm-8 text-muted">0</dd>
						<dt class="col-sm-4">{{ $__t('READY rows') }}</dt>
						<dd id="summary-ready" class="col-sm-8 text-muted">0</dd>
						<dt class="col-sm-4">{{ $__t('Status counts') }}</dt>
						<dd id="summary-statuses" class="col-sm-8 text-muted">-</dd>
					</dl>
				</div>
			</div>
		</div>
	</div>
</div>

<div class="row mb-2">
	<div class="col-12 col-md-6 col-xl-4">
		<div class="input-group">
			<div class="input-group-prepend">
				<span class="input-group-text"><i class="fa-solid fa-search"></i></span>
			</div>
			<input id="receipt-review-search"
				class="form-control"
				type="text"
				placeholder="{{ $__t('Filter rows by description or status') }}">
		</div>
	</div>
</div>

<div class="row">
	<div class="col">
		<div class="table-responsive">
			<table class="table table-sm table-striped receipt-review-table">
				<thead>
					<tr>
						<th>{{ $__t('Line') }}</th>
						<th>{{ $__t('Description') }}</th>
						<th>{{ $__t('Status') }}</th>
						<th>{{ $__t('Product override') }}</th>
						<th>{{ $__t('Selected product') }}</th>
						<th>{{ $__t('Stock entry override') }}</th>
						<th>{{ $__t('Selected stock entry') }}</th>
						<th>{{ $__t('Price check') }}</th>
						<th>{{ $__t('Apply') }}</th>
					</tr>
				</thead>
				<tbody id="receipt-review-table-body">
					<tr>
						<td colspan="9" class="text-muted">{{ $__t('Load staging JSON to begin reviewing rows.') }}</td>
					</tr>
				</tbody>
			</table>
		</div>
	</div>
</div>
@stop