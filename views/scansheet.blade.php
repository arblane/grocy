@extends('layout.default')

@section('title', $__t('Scan Sheet'))

@push('pageStyles')
<style>
	@media print {
		.page:not(:last-child) {
			page-break-after: always !important;
		}

		.page.no-page-break {
			page-break-after: avoid !important;
		}

		.scansheet-grid {
			grid-template-columns: repeat(3, minmax(0, 1fr)) !important;
			gap: 0.3rem;
		}

		.scansheet-item {
			padding: 0.2rem;
		}

		.scansheet-label {
			font-size: 0.85rem;
		}

		.scansheet-grocycode {
			display: block;
			max-width: 100%;
		}
	}

	.scansheet-grid {
		display: grid;
		grid-template-columns: repeat(3, minmax(0, 1fr));
		gap: 0.6rem;
	}

	@media (max-width: 992px) {
		.scansheet-grid {
			grid-template-columns: repeat(2, minmax(0, 1fr));
		}
	}

	@media (max-width: 576px) {
		.scansheet-grid {
			grid-template-columns: 1fr;
		}
	}

	.scansheet-item {
		border: 1px solid #d9d9d9;
		border-radius: 4px;
		padding: 0.5rem;
		text-align: center;
	}

	.scansheet-label {
		font-weight: 600;
		line-height: 1.2;
		margin-bottom: 0.35rem;
		min-height: 2.4em;
	}

	/* Force white background on Grocycode images so they scan reliably in any theme/dark mode */
	.scansheet-grocycode {
		display: block;
		margin: 0 auto;
		background: #ffffff;
		padding: 3px;
		border: 1px solid #cccccc;
	}
</style>
@endpush

@section('content')
<div class="title-related-links d-print-none">
	<h2 class="title">
		@yield('title')
		<i class="fa-solid fa-question-circle text-muted small"
			data-toggle="tooltip"
			data-trigger="hover click"
			title="{{ $__t('Products flagged for the scan sheet, grouped by their default storage location') }}"></i>
	</h2>
	<div class="float-right">
		<button class="btn btn-outline-dark d-md-none mt-2 order-1 order-md-3"
			type="button"
			data-toggle="collapse"
			data-target="#related-links">
			<i class="fa-solid fa-ellipsis-v"></i>
		</button>
	</div>
	<div class="related-links collapse d-md-flex order-2 width-xs-sm-100"
		id="related-links">
		<a class="btn btn-outline-dark responsive-button m-1 mt-md-0 mb-md-0 float-right print-all-locations-button"
			href="#">
			{{ $__t('Print') . ' (' . $__t('all locations') . ')' }}
		</a>
	</div>
</div>

<hr class="my-2 d-print-none">

@if(empty($pages))
<p class="text-muted d-print-none">
	{{ $__t('No products are flagged for the scan sheet. Enable the "Include in scan sheet" userfield on any product to have it appear here.') }}
</p>
@endif

@foreach($pages as $page)
@php $pageHasProducts = !empty(array_merge(...array_column($page['sections'], 'products'))); @endphp
@if(!$pageHasProducts)
@continue
@endif
<div class="page">
	<h1 class="pt-4 text-center">
		<img src="{{ $U('/img/logo.svg?v=', true) }}{{ $version }}"
			width="114"
			height="30"
			class="d-none d-print-flex mx-auto">
		{{ $page['title'] }}
		<a class="btn btn-outline-dark btn-sm responsive-button print-single-location-button d-print-none"
			href="#">
			{{ $__t('Print') . ' (' . $__t('this location') . ')' }}
		</a>
	</h1>
	<h6 class="mb-4 d-none d-print-block text-center">
		{{ $__t('Time of printing') }}:
		<span class="d-inline print-timestamp"></span>
	</h6>
	@foreach($page['sections'] as $section)
	@if(!empty($section['title']))
	<h4 class="mt-3 mb-2">{{ $section['title'] }}</h4>
	@endif
	<div class="scansheet-grid">
		@foreach($section['products'] as $product)
		@php
			$brand = trim((string) ($product->brand ?? ''));
			$displayName = trim((string) ($product->product_display_name ?? $product->name));
			$label = $displayName;
			if (!empty($brand))
			{
				$label = $brand . ' - ' . $displayName;
			}
		@endphp
		<div class="scansheet-item">
			<div class="scansheet-label">{{ $label }}</div>
			<img class="scansheet-grocycode"
				src="{{ $U('/product/' . $product->id . '/grocycode?size=50') }}"
				alt="grocy:p:{{ $product->id }}">
		</div>
		@endforeach
	</div>
	@endforeach
</div>
@endforeach
@stop
