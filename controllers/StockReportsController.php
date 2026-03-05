<?php

namespace Grocy\Controllers;

use Psr\Http\Message\ResponseInterface as Response;
use Psr\Http\Message\ServerRequestInterface as Request;

class StockReportsController extends BaseController
{
	public function Consumption(Request $request, Response $response, array $args)
	{
		$selectedProductId = null;
		if (isset($request->getQueryParams()['product']) && is_numeric($request->getQueryParams()['product']))
		{
			$candidateProductId = (int)$request->getQueryParams()['product'];
			if ($candidateProductId > 0 && $this->getDatabase()->products($candidateProductId) !== null)
			{
				$selectedProductId = $candidateProductId;
			}
		}

		$where = "sl.transaction_type = 'consume' AND sl.undone = 0 AND sl.amount < 0";
		if ($selectedProductId !== null)
		{
			$where .= ' AND sl.product_id = ' . $selectedProductId;
		}

		$sql = "
		SELECT
			sl.product_id,
			p.name AS product_name,
			COALESCE(sl.transaction_id, sl.id) AS consume_event_key,
			MIN(sl.row_created_timestamp) AS consumed_at
		FROM stock_log sl
		JOIN products p
			ON sl.product_id = p.id
		WHERE $where
		GROUP BY sl.product_id, p.name, COALESCE(sl.transaction_id, sl.id)
		ORDER BY p.name COLLATE NOCASE, consumed_at
		";

		$consumeEvents = $this->getDatabaseService()->ExecuteDbQuery($sql)->fetchAll(\PDO::FETCH_OBJ);
		$metricsByProduct = [];

		foreach ($consumeEvents as $consumeEvent)
		{
			$productId = (int)$consumeEvent->product_id;
			if (!array_key_exists($productId, $metricsByProduct))
			{
				$metricsByProduct[$productId] = (object) [
					'product_id' => $productId,
					'product_name' => $consumeEvent->product_name,
					'consume_event_count' => 0,
					'average_days_between_consumptions' => null,
					'last_consumed_at' => null,
					'_timestamps' => [],
				];
			}

			$currentTimestamp = strtotime($consumeEvent->consumed_at);
			if ($currentTimestamp === false)
			{
				continue;
			}

			$metricsByProduct[$productId]->consume_event_count++;
			$metricsByProduct[$productId]->_timestamps[] = $currentTimestamp;
			$metricsByProduct[$productId]->last_consumed_at = $consumeEvent->consumed_at;
		}

		$metrics = [];
		foreach ($metricsByProduct as $metric)
		{
			$totalIntervalDays = 0.0;
			$intervalCount = 0;

			for ($index = 1; $index < count($metric->_timestamps); $index++)
			{
				$intervalSeconds = $metric->_timestamps[$index] - $metric->_timestamps[$index - 1];
				if ($intervalSeconds >= 0)
				{
					$totalIntervalDays += $intervalSeconds / 86400;
					$intervalCount++;
				}
			}

			if ($intervalCount > 0)
			{
				$metric->average_days_between_consumptions = round($totalIntervalDays / $intervalCount, 2);
			}

			$metric->confidence_score = 0;
			$metric->confidence_label = 'n/a';
			$metric->confidence_badge_class = 'secondary';

			if ($metric->consume_event_count >= 20)
			{
				$metric->confidence_score = 3;
				$metric->confidence_label = 'High';
				$metric->confidence_badge_class = 'success';
			}
			elseif ($metric->consume_event_count >= 8)
			{
				$metric->confidence_score = 2;
				$metric->confidence_label = 'Medium';
				$metric->confidence_badge_class = 'info';
			}
			elseif ($metric->consume_event_count >= 3)
			{
				$metric->confidence_score = 1;
				$metric->confidence_label = 'Low';
				$metric->confidence_badge_class = 'warning';
			}

			unset($metric->_timestamps);
			$metrics[] = $metric;
		}

		return $this->renderPage($response, 'stockreportsconsumption', [
			'metrics' => $metrics,
			'products' => $this->getDatabase()->products()->orderBy('name', 'COLLATE NOCASE'),
			'selectedProductId' => $selectedProductId
		]);
	}

	public function Spendings(Request $request, Response $response, array $args)
	{
		$where = "pph.transaction_type != 'self-production'";

		if (isset($request->getQueryParams()['start_date']) && isset($request->getQueryParams()['end_date']) && IsIsoDate($request->getQueryParams()['start_date']) && IsIsoDate($request->getQueryParams()['end_date']))
		{
			$startDate = $request->getQueryParams()['start_date'];
			$endDate = $request->getQueryParams()['end_date'];
			$where .= " AND pph.purchased_date BETWEEN '$startDate' AND '$endDate'";
		}
		else
		{
			// Default to this month
			$where .= " AND pph.purchased_date >= DATE(DATE('now', 'localtime'), 'start of month')";
		}

		$groupBy = 'product';
		if (isset($request->getQueryParams()['group-by']) && in_array($request->getQueryParams()['group-by'], ['product', 'productgroup', 'store']))
		{
			$groupBy = $request->getQueryParams()['group-by'];
		}

		if ($groupBy == 'product')
		{
			if (isset($request->getQueryParams()['product-group']))
			{
				if ($request->getQueryParams()['product-group'] == 'ungrouped')
				{
					$where .= ' AND pg.id IS NULL';
				}
				elseif ($request->getQueryParams()['product-group'] != 'all')
				{
					$where .= ' AND pg.id = ' . $request->getQueryParams()['product-group'];
				}
			}

			$sql = "
			SELECT
				p.id AS id,
				p.name AS name,
				pg.id AS group_id,
				pg.name AS group_name,
				SUM(pph.amount * pph.price) AS total
			FROM products_price_history pph
			JOIN products p
				ON pph.product_id = p.id
			LEFT JOIN product_groups pg
				ON p.product_group_id = pg.id
			WHERE $where
			GROUP BY p.id, p.name, pg.id, pg.name
			ORDER BY p.name COLLATE NOCASE
			";
		}
		elseif ($groupBy == 'productgroup')
		{
			$sql = "
			SELECT
				pg.id AS id,
				pg.name AS name,
				SUM(pph.amount * pph.price) AS total
			FROM products_price_history pph
			JOIN products p
				ON pph.product_id = p.id
			LEFT JOIN product_groups pg
				ON p.product_group_id = pg.id
			WHERE $where
			GROUP BY pg.id, pg.name
			ORDER BY pg.name COLLATE NOCASE
			";
		}
		elseif ($groupBy == 'store')
		{
			$sql = "
			SELECT
				sl.id AS id,
				sl.name AS name,
				SUM(pph.amount * pph.price) AS total
			FROM products_price_history pph
			JOIN products p
				ON pph.product_id = p.id
			LEFT JOIN shopping_locations sl
				ON pph.shopping_location_id = sl.id
			WHERE $where
			GROUP BY sl.id, sl.name
			ORDER BY sl.NAME COLLATE NOCASE
			";
		}

		return $this->renderPage($response, 'stockreportspendings', [
			'metrics' => $this->getDatabaseService()->ExecuteDbQuery($sql)->fetchAll(\PDO::FETCH_OBJ),
			'productGroups' => $this->getDatabase()->product_groups()->where('active = 1')->orderBy('name', 'COLLATE NOCASE'),
			'selectedGroup' => isset($request->getQueryParams()['product-group']) ? $request->getQueryParams()['product-group'] : null,
			'groupBy' => $groupBy
		]);
	}
}
