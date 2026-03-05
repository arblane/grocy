@php require_frontend_packages(['datatables']); @endphp

@extends('layout.default')

@section('title', $__t('Stock report') . ' / ' . $__t('Consumption rates'))

@section('content')
<div class="row">
	<div class="col">
		<h2 class="title">@yield('title')</h2>
		<div class="float-right @if($embedded) pr-5 @endif">
			<button class="btn btn-outline-dark d-md-none mt-2 order-1 order-md-3"
				type="button"
				data-toggle="collapse"
				data-target="#table-filter-row">
				<i class="fa-solid fa-filter"></i>
			</button>
		</div>
	</div>
</div>

<hr class="my-2">

<div class="row collapse d-md-flex"
	id="table-filter-row">
	<div class="col-12 col-md-8 col-xl-5">
		<div class="input-group">
			<div class="input-group-prepend">
				<span class="input-group-text"><i class="fa-solid fa-filter"></i>&nbsp;{{ $__t('Product') }}</span>
			</div>
			<select class="custom-control custom-select"
				id="product-filter">
				<option value="all">{{ $__t('All') }}</option>
				@foreach($products as $product)
				<option value="{{ $product->id }}"
					@if($selectedProductId !== null && (int)$product->id === (int)$selectedProductId) selected="selected" @endif>
					#{{ $product->id }} - {{ $product->name }}
				</option>
				@endforeach
			</select>
		</div>
	</div>
	<div class="col">
		<div class="float-right mt-1">
			<button id="clear-filter-button"
				class="btn btn-sm btn-outline-info"
				data-toggle="tooltip"
				title="{{ $__t('Clear filter') }}">
				<i class="fa-solid fa-filter-circle-xmark"></i>
			</button>
		</div>
	</div>
</div>

<div class="row mt-2">
	<div class="col">
		<table id="consumption-metrics-table"
			class="table table-sm table-striped nowrap w-100">
			<thead>
				<tr>
					<th>{{ $__t('Product') }}</th>
					<th>{{ $__t('Consumptions') }}</th>
					<th>{{ $__t('Confidence') }}</th>
					<th>{{ $__t('Average') }} {{ $__t('days') }}</th>
					<th>{{ $__t('Last used') }}</th>
				</tr>
			</thead>
			<tbody class="d-none">
				@foreach($metrics as $metric)
				<tr>
					<td>{{ $metric->product_name }}</td>
					<td data-order="{{ $metric->consume_event_count }}">{{ $metric->consume_event_count }}</td>
					<td data-order="{{ $metric->confidence_score }}">
						@if($metric->confidence_score === 0)
						<span class="text-muted">{{ $__t('n/a') }}</span>
						@else
						<span class="badge badge-{{ $metric->confidence_badge_class }}">{{ $__t($metric->confidence_label) }}</span>
						@endif
					</td>
					<td data-order="{{ $metric->average_days_between_consumptions === null ? -1 : $metric->average_days_between_consumptions }}">
						@if($metric->average_days_between_consumptions === null)
						<span class="text-muted">{{ $__t('n/a') }}</span>
						@else
						<span class="locale-number">{{ $metric->average_days_between_consumptions }}</span>
						@endif
					</td>
					<td>
						@if(empty($metric->last_consumed_at))
						<span class="text-muted">{{ $__t('n/a') }}</span>
						@else
						<span class="datetime-localized">{{ $metric->last_consumed_at }}</span>
						@endif
					</td>
				</tr>
				@endforeach
			</tbody>
		</table>
	</div>
</div>
@stop
