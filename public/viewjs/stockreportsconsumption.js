var consumptionMetricsTable = $("#consumption-metrics-table").DataTable({
	"order": [[4, "asc"], [0, "asc"]],
	"columnDefs": [
		{ "type": "num", "targets": [1, 2, 3, 4] }
	].concat($.fn.dataTable.defaults.columnDefs)
});
$("#consumption-metrics-table tbody").removeClass("d-none");
consumptionMetricsTable.columns.adjust().draw();

$("#product-filter").on("change", function()
{
	var selectedProductId = $(this).val();
	if (selectedProductId === "all")
	{
		RemoveUriParam("product");
	}
	else
	{
		UpdateUriParam("product", selectedProductId);
	}

	window.location.reload();
});

$("#clear-filter-button").on("click", function()
{
	RemoveUriParam("product");
	window.location.reload();
});
