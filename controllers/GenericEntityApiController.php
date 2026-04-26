<?php

namespace Grocy\Controllers;

use Grocy\Controllers\Users\User;
use Psr\Http\Message\ResponseInterface as Response;
use Psr\Http\Message\ServerRequestInterface as Request;

class GenericEntityApiController extends BaseApiController
{
	private static $NullableNumericDateColumns = null;

	private function BuildProductDisplayName($product)
	{
		if ($product === null)
		{
			return '';
		}

		$parts = [];
		if (!empty($product->name))
		{
			$parts[] = trim($product->name);
		}
		if (!empty($product->additional_details))
		{
			$parts[] = trim($product->additional_details);
		}
		if (!empty($product->strength))
		{
			$parts[] = trim($product->strength);
		}
		if (!empty($product->size))
		{
			$parts[] = trim($product->size);
		}
		if (!empty($product->package_configuration))
		{
			$parts[] = trim($product->package_configuration);
		}

		$displayName = implode(', ', array_filter($parts, function ($part)
		{
			return $part !== '';
		}));

		if (!empty($product->brand) && trim($product->brand) !== '')
		{
			$displayName .= ' - ' . trim($product->brand);
		}

		return $displayName;
	}

	private function EnrichProductsEntityWithDisplayName($entity, $object)
	{
		if ($entity !== 'products' || $object === null)
		{
			return;
		}

		$object->product_display_name = $this->BuildProductDisplayName($object);
	}

	public function AddObject(Request $request, Response $response, array $args)
	{
		if ($args['entity'] == 'shopping_list' || $args['entity'] == 'shopping_lists')
		{
			User::checkPermission($request, User::PERMISSION_SHOPPINGLIST_ITEMS_ADD);
		}
		elseif ($args['entity'] == 'recipes' || $args['entity'] == 'recipes_pos' || $args['entity'] == 'recipes_nestings')
		{
			User::checkPermission($request, User::PERMISSION_RECIPES);
		}
		elseif ($args['entity'] == 'meal_plan')
		{
			User::checkPermission($request, User::PERMISSION_RECIPES_MEALPLAN);
		}
		elseif ($args['entity'] == 'equipment')
		{
			User::checkPermission($request, User::PERMISSION_EQUIPMENT);
		}
		else
		{
			User::checkPermission($request, User::PERMISSION_MASTER_DATA_EDIT);
		}

		if ($this->IsValidExposedEntity($args['entity']) && !$this->IsEntityWithNoEdit($args['entity']))
		{
			if ($this->IsEntityWithEditRequiresAdmin($args['entity']))
			{
				User::checkPermission($request, User::PERMISSION_ADMIN);
			}

			$requestBody = $this->GetParsedAndFilteredRequestBody($request);
			$requestBody = $this->NormalizeEmptyStringsForNullableColumns($args['entity'], $requestBody);
			if ($args['entity'] == 'tasks')
			{
				if (isset($requestBody['category_id']) && $requestBody['category_id'] === '')
				{
					unset($requestBody['category_id']);
				}
				if (isset($requestBody['due_date']) && $requestBody['due_date'] === '')
				{
					unset($requestBody['due_date']);
				}
			}
			if ($args['entity'] == 'chores')
			{
				if (isset($requestBody['product_id']) && $requestBody['product_id'] === '')
				{
					unset($requestBody['product_id']);
				}
			}
			if ($args['entity'] == 'userfields')
			{
				if (isset($requestBody['sort_number']) && $requestBody['sort_number'] === '')
				{
					unset($requestBody['sort_number']);
				}
			}

			$syncInverseQuConversions = $this->ShouldSyncInverseQuantityUnitConversions($args['entity']);
			$dbConnection = $this->getDatabaseService()->GetDbConnectionRaw();

			try
			{
				if ($syncInverseQuConversions)
				{
					$dbConnection->beginTransaction();
				}

				if ($requestBody === null)
				{
					throw new \Exception('Request body could not be parsed (probably invalid JSON format or missing/wrong Content-Type header)');
				}

				$newRow = $this->getDatabase()->{$args['entity']}()->createRow($requestBody);
				$newRow->save();
				$newObjectId = $this->getDatabase()->lastInsertId();

				if ($syncInverseQuConversions)
				{
					$this->SyncInverseQuantityUnitConversionById((int) $newObjectId);
				}

				// TODO: This should be better done somehow in StockService
				if ($args['entity'] == 'products' && boolval($this->getUsersService()->GetUserSetting(GROCY_USER_ID, 'shopping_list_auto_add_below_min_stock_amount')))
				{
					$this->getStockService()->AddMissingProductsToShoppingList($this->getUsersService()->GetUserSetting(GROCY_USER_ID, 'shopping_list_auto_add_below_min_stock_amount_list_id'));
				}

				if ($syncInverseQuConversions)
				{
					$dbConnection->commit();
				}

				return $this->ApiResponse($response, [
					'created_object_id' => $newObjectId
				]);
			}
			catch (\Exception $ex)
			{
				if ($syncInverseQuConversions && $dbConnection->inTransaction())
				{
					$dbConnection->rollBack();
				}

				return $this->GenericErrorResponse($response, $ex->getMessage());
			}
		}
		else
		{
			return $this->GenericErrorResponse($response, 'Entity does not exist or is not exposed');
		}
	}

	public function DeleteObject(Request $request, Response $response, array $args)
	{
		if ($args['entity'] == 'shopping_list' || $args['entity'] == 'shopping_lists')
		{
			User::checkPermission($request, User::PERMISSION_SHOPPINGLIST_ITEMS_DELETE);
		}
		elseif ($args['entity'] == 'recipes' || $args['entity'] == 'recipes_pos' || $args['entity'] == 'recipes_nestings')
		{
			User::checkPermission($request, User::PERMISSION_RECIPES);
		}
		elseif ($args['entity'] == 'meal_plan')
		{
			User::checkPermission($request, User::PERMISSION_RECIPES_MEALPLAN);
		}
		elseif ($args['entity'] == 'equipment')
		{
			User::checkPermission($request, User::PERMISSION_EQUIPMENT);
		}
		elseif ($args['entity'] == 'api_keys')
		{
			// Always allowed
		}
		else
		{
			User::checkPermission($request, User::PERMISSION_MASTER_DATA_EDIT);
		}

		if ($this->IsValidExposedEntity($args['entity']) && !$this->IsEntityWithNoDelete($args['entity']))
		{
			if ($this->IsEntityWithEditRequiresAdmin($args['entity']))
			{
				User::checkPermission($request, User::PERMISSION_ADMIN);
			}

			$syncInverseQuConversions = $this->ShouldSyncInverseQuantityUnitConversions($args['entity']);
			$dbConnection = $this->getDatabaseService()->GetDbConnectionRaw();
			$quConversionRow = null;

			$row = $this->getDatabase()->{$args['entity']}($args['objectId']);
			if ($row == null)
			{
				return $this->GenericErrorResponse($response, 'Object not found', 400);
			}

			try
			{
				if ($syncInverseQuConversions)
				{
					$dbConnection->beginTransaction();
					$quConversionRow = $this->GetQuantityUnitConversionById((int) $args['objectId']);
				}

				$row->delete();

				if ($syncInverseQuConversions && $quConversionRow !== null)
				{
					$this->DeleteInverseQuantityUnitConversion($quConversionRow);
				}

				if ($syncInverseQuConversions)
				{
					$dbConnection->commit();
				}

				return $this->EmptyApiResponse($response);
			}
			catch (\Exception $ex)
			{
				if ($syncInverseQuConversions && $dbConnection->inTransaction())
				{
					$dbConnection->rollBack();
				}

				return $this->GenericErrorResponse($response, $ex->getMessage());
			}
		}
		else
		{
			return $this->GenericErrorResponse($response, 'Invalid entity');
		}
	}

	public function EditObject(Request $request, Response $response, array $args)
	{
		if ($args['entity'] == 'shopping_list' || $args['entity'] == 'shopping_lists')
		{
			User::checkPermission($request, User::PERMISSION_SHOPPINGLIST_ITEMS_ADD);
		}
		elseif ($args['entity'] == 'recipes' || $args['entity'] == 'recipes_pos' || $args['entity'] == 'recipes_nestings')
		{
			User::checkPermission($request, User::PERMISSION_RECIPES);
		}
		elseif ($args['entity'] == 'meal_plan')
		{
			User::checkPermission($request, User::PERMISSION_RECIPES_MEALPLAN);
		}
		elseif ($args['entity'] == 'equipment')
		{
			User::checkPermission($request, User::PERMISSION_EQUIPMENT);
		}
		else
		{
			User::checkPermission($request, User::PERMISSION_MASTER_DATA_EDIT);
		}

		if ($this->IsValidExposedEntity($args['entity']) && !$this->IsEntityWithNoEdit($args['entity']))
		{
			if ($this->IsEntityWithEditRequiresAdmin($args['entity']))
			{
				User::checkPermission($request, User::PERMISSION_ADMIN);
			}

			$requestBody = $this->GetParsedAndFilteredRequestBody($request);
			$requestBody = $this->NormalizeEmptyStringsForNullableColumns($args['entity'], $requestBody);
			if ($args['entity'] == 'tasks')
			{
				if (isset($requestBody['category_id']) && $requestBody['category_id'] === '')
				{
					unset($requestBody['category_id']);
				}
				if (isset($requestBody['due_date']) && $requestBody['due_date'] === '')
				{
					unset($requestBody['due_date']);
				}
			}
			if ($args['entity'] == 'chores')
			{
				if (isset($requestBody['product_id']) && $requestBody['product_id'] === '')
				{
					unset($requestBody['product_id']);
				}
			}
			if ($args['entity'] == 'userfields')
			{
				if (isset($requestBody['sort_number']) && $requestBody['sort_number'] === '')
				{
					unset($requestBody['sort_number']);
				}
			}

			$syncInverseQuConversions = $this->ShouldSyncInverseQuantityUnitConversions($args['entity']);
			$dbConnection = $this->getDatabaseService()->GetDbConnectionRaw();
			$oldQuConversionRow = null;

			try
			{
				if ($syncInverseQuConversions)
				{
					$dbConnection->beginTransaction();
				}

				if ($requestBody === null)
				{
					throw new \Exception('Request body could not be parsed (probably invalid JSON format or missing/wrong Content-Type header)');
				}

				$row = $this->getDatabase()->{$args['entity']}($args['objectId']);
				if ($row == null)
				{
					throw new \Exception('Object not found');
				}

				if ($syncInverseQuConversions)
				{
					$oldQuConversionRow = $this->GetQuantityUnitConversionById((int) $args['objectId']);
				}

				$row->update($requestBody);

				if ($syncInverseQuConversions)
				{
					$newQuConversionRow = $this->GetQuantityUnitConversionById((int) $args['objectId']);
					if ($oldQuConversionRow !== null && $newQuConversionRow !== null && !$this->IsSameQuantityUnitConversionRelation($oldQuConversionRow, $newQuConversionRow))
					{
						$this->DeleteInverseQuantityUnitConversion($oldQuConversionRow, (int) $args['objectId']);
					}

					$this->SyncInverseQuantityUnitConversionById((int) $args['objectId']);
				}

				// TODO: This should be better done somehow in StockService
				if ($args['entity'] == 'products' && boolval($this->getUsersService()->GetUserSetting(GROCY_USER_ID, 'shopping_list_auto_add_below_min_stock_amount')))
				{
					$this->getStockService()->AddMissingProductsToShoppingList($this->getUsersService()->GetUserSetting(GROCY_USER_ID, 'shopping_list_auto_add_below_min_stock_amount_list_id'));
				}

				if ($syncInverseQuConversions)
				{
					$dbConnection->commit();
				}

				return $this->EmptyApiResponse($response);
			}
			catch (\Exception $ex)
			{
				if ($syncInverseQuConversions && $dbConnection->inTransaction())
				{
					$dbConnection->rollBack();
				}

				return $this->GenericErrorResponse($response, $ex->getMessage());
			}
		}
		else
		{
			return $this->GenericErrorResponse($response, 'Entity does not exist or is not exposed');
		}
	}

	public function GetObject(Request $request, Response $response, array $args)
	{
		if (!$this->IsValidExposedEntity($args['entity']) || $this->IsEntityWithNoListing($args['entity']))
		{
			return $this->GenericErrorResponse($response, 'Entity does not exist or is not exposed');
		}

		$object = $this->getDatabase()->{$args['entity']}($args['objectId']);
		if ($object == null)
		{
			return $this->GenericErrorResponse($response, 'Object not found', 404);
		}

		$this->EnrichProductsEntityWithDisplayName($args['entity'], $object);

		// TODO: Handle this somehow more generically
		$referencingId = $args['objectId'];
		if ($args['entity'] == 'stock')
		{
			$referencingId = $object->stock_id;
		}
		$userfields = $this->getUserfieldsService()->GetValues($args['entity'], $referencingId);
		if (count($userfields) === 0)
		{
			$userfields = null;
		}
		$object['userfields'] = $userfields;

		return $this->ApiResponse($response, $object);
	}

	public function GetObjects(Request $request, Response $response, array $args)
	{
		if (!$this->IsValidExposedEntity($args['entity']) || $this->IsEntityWithNoListing($args['entity']))
		{
			return $this->GenericErrorResponse($response, 'Entity does not exist or is not exposed');
		}

		$objects = $this->queryData($this->getDatabase()->{$args['entity']}(), $request->getQueryParams());

		if ($args['entity'] === 'products')
		{
			foreach ($objects as $object)
			{
				$this->EnrichProductsEntityWithDisplayName($args['entity'], $object);
			}
		}

		$userfields = $this->getUserfieldsService()->GetFields($args['entity']);
		if (count($userfields) > 0)
		{
			$allUserfieldValues = $this->getUserfieldsService()->GetAllValues($args['entity']);

			foreach ($objects as $object)
			{
				$userfieldKeyValuePairs = null;
				foreach ($userfields as $userfield)
				{
					// TODO: Handle this somehow more generically
					$userfieldReference = 'id';
					if ($args['entity'] == 'stock')
					{
						$userfieldReference = 'stock_id';
					}

					$value = FindObjectInArrayByPropertyValue(FindAllObjectsInArrayByPropertyValue($allUserfieldValues, 'object_id', $object->{$userfieldReference}), 'name', $userfield->name);
					if ($value)
					{
						$userfieldKeyValuePairs[$userfield->name] = $value->value;
					}
					else
					{
						$userfieldKeyValuePairs[$userfield->name] = null;
					}
				}

				$object->userfields = $userfieldKeyValuePairs;
			}
		}

		return $this->ApiResponse($response, $objects);
	}

	public function GetUserfields(Request $request, Response $response, array $args)
	{
		try
		{
			return $this->ApiResponse($response, $this->getUserfieldsService()->GetValues($args['entity'], $args['objectId']));
		}
		catch (\Exception $ex)
		{
			return $this->GenericErrorResponse($response, $ex->getMessage());
		}
	}

	public function SetUserfields(Request $request, Response $response, array $args)
	{
		User::checkPermission($request, User::PERMISSION_MASTER_DATA_EDIT);

		$requestBody = $this->GetParsedAndFilteredRequestBody($request);

		try
		{
			if ($requestBody === null)
			{
				throw new \Exception('Request body could not be parsed (probably invalid JSON format or missing/wrong Content-Type header)');
			}

			$this->getUserfieldsService()->SetValues($args['entity'], $args['objectId'], $requestBody);
			return $this->EmptyApiResponse($response);
		}
		catch (\Exception $ex)
		{
			return $this->GenericErrorResponse($response, $ex->getMessage());
		}
	}

	private function ShouldSyncInverseQuantityUnitConversions($entity)
	{
		return $entity === 'quantity_unit_conversions' && $this->getDatabaseService()->GetDatabaseType() !== 'sqlite';
	}

	private function GetQuantityUnitConversionById($id)
	{
		$statement = $this->getDatabaseService()->GetDbConnectionRaw()->prepare('SELECT id, from_qu_id, to_qu_id, factor, product_id FROM quantity_unit_conversions WHERE id = ? LIMIT 1');
		$statement->execute([$id]);
		$row = $statement->fetch(\PDO::FETCH_ASSOC);

		if ($row === false)
		{
			return null;
		}

		return [
			'id' => (int) $row['id'],
			'from_qu_id' => (int) $row['from_qu_id'],
			'to_qu_id' => (int) $row['to_qu_id'],
			'factor' => (float) $row['factor'],
			'product_id' => $row['product_id'] === null ? null : (int) $row['product_id']
		];
	}

	private function SyncInverseQuantityUnitConversionById($id)
	{
		$sourceRow = $this->GetQuantityUnitConversionById($id);
		if ($sourceRow === null)
		{
			return;
		}

		$this->EnsureInverseQuantityUnitConversion($sourceRow);
	}

	private function EnsureInverseQuantityUnitConversion($sourceRow)
	{
		if ((int) $sourceRow['from_qu_id'] === (int) $sourceRow['to_qu_id'])
		{
			return;
		}

		if ((float) $sourceRow['factor'] == 0.0)
		{
			throw new \Exception('Factor cannot be zero');
		}

		$dbConnection = $this->getDatabaseService()->GetDbConnectionRaw();
		$inverseFactor = 1 / (float) $sourceRow['factor'];

		$selectInverseIds = $dbConnection->prepare(
			'SELECT id
			FROM quantity_unit_conversions
			WHERE from_qu_id = ?
				AND to_qu_id = ?
				AND ((product_id IS NULL AND ? IS NULL) OR product_id = ?)
				AND id != ?
			ORDER BY id'
		);
		$selectInverseIds->execute([
			(int) $sourceRow['to_qu_id'],
			(int) $sourceRow['from_qu_id'],
			$sourceRow['product_id'],
			$sourceRow['product_id'],
			(int) $sourceRow['id']
		]);

		$inverseIds = array_map('intval', $selectInverseIds->fetchAll(\PDO::FETCH_COLUMN));
		if (count($inverseIds) === 0)
		{
			$insertInverse = $dbConnection->prepare(
				'INSERT INTO quantity_unit_conversions
					(from_qu_id, to_qu_id, factor, product_id)
				VALUES
					(?, ?, ?, ?)'
			);
			$insertInverse->execute([
				(int) $sourceRow['to_qu_id'],
				(int) $sourceRow['from_qu_id'],
				$inverseFactor,
				$sourceRow['product_id']
			]);

			return;
		}

		$keepId = $inverseIds[0];

		if (count($inverseIds) > 1)
		{
			$inverseIdsToDelete = array_slice($inverseIds, 1);
			$placeholders = implode(', ', array_fill(0, count($inverseIdsToDelete), '?'));
			$deleteDuplicates = $dbConnection->prepare('DELETE FROM quantity_unit_conversions WHERE id IN (' . $placeholders . ')');
			$deleteDuplicates->execute($inverseIdsToDelete);
		}

		$updateInverse = $dbConnection->prepare(
			'UPDATE quantity_unit_conversions
			SET from_qu_id = ?,
				to_qu_id = ?,
				factor = ?,
				product_id = ?
			WHERE id = ?'
		);
		$updateInverse->execute([
			(int) $sourceRow['to_qu_id'],
			(int) $sourceRow['from_qu_id'],
			$inverseFactor,
			$sourceRow['product_id'],
			$keepId
		]);
	}

	private function DeleteInverseQuantityUnitConversion($sourceRow, $excludeId = null)
	{
		if ((int) $sourceRow['from_qu_id'] === (int) $sourceRow['to_qu_id'])
		{
			return;
		}

		$sql =
			'DELETE FROM quantity_unit_conversions
			WHERE from_qu_id = ?
				AND to_qu_id = ?
				AND ((product_id IS NULL AND ? IS NULL) OR product_id = ?)';
		$params = [
			(int) $sourceRow['to_qu_id'],
			(int) $sourceRow['from_qu_id'],
			$sourceRow['product_id'],
			$sourceRow['product_id']
		];

		if ($excludeId !== null)
		{
			$sql .= ' AND id != ?';
			$params[] = (int) $excludeId;
		}

		$deleteInverse = $this->getDatabaseService()->GetDbConnectionRaw()->prepare($sql);
		$deleteInverse->execute($params);
	}

	private function IsSameQuantityUnitConversionRelation($leftRow, $rightRow)
	{
		if ((int) $leftRow['from_qu_id'] !== (int) $rightRow['from_qu_id'])
		{
			return false;
		}

		if ((int) $leftRow['to_qu_id'] !== (int) $rightRow['to_qu_id'])
		{
			return false;
		}

		if ($leftRow['product_id'] === null && $rightRow['product_id'] === null)
		{
			return true;
		}

		return (int) $leftRow['product_id'] === (int) $rightRow['product_id'];
	}

	private function NormalizeEmptyStringsForNullableColumns($entity, $requestBody)
	{
		if ($requestBody === null || !is_array($requestBody))
		{
			return $requestBody;
		}

		if ($this->getDatabaseService()->GetDatabaseType() === 'sqlite')
		{
			return $requestBody;
		}

		$entityName = strtolower(preg_replace('/List$/', '', $entity));
		if (self::$NullableNumericDateColumns === null)
		{
			$dbName = defined('GROCY_DATABASE_NAME') ? GROCY_DATABASE_NAME : 'grocy';
			$pdo = $this->getDatabaseService()->GetDbConnectionRaw();
			$stmt = $pdo->prepare(
				"SELECT table_name, column_name FROM information_schema.columns "
				. "WHERE table_schema = :db "
				. "AND is_nullable = 'YES' "
				. "AND data_type IN ('int','tinyint','smallint','mediumint','bigint','decimal','float','double','date','datetime','timestamp')"
			);
			$stmt->execute([':db' => $dbName]);
			$map = [];
			foreach ($stmt->fetchAll(\PDO::FETCH_ASSOC) as $row)
			{
				$table = strtolower($row['table_name']);
				$column = strtolower($row['column_name']);
				if (!isset($map[$table]))
				{
					$map[$table] = [];
				}
				$map[$table][$column] = true;
			}
			self::$NullableNumericDateColumns = $map;
		}

		if (!isset(self::$NullableNumericDateColumns[$entityName]))
		{
			return $requestBody;
		}

		$nullableColumns = self::$NullableNumericDateColumns[$entityName];
		foreach ($requestBody as $key => $value)
		{
			if ($value === '' && isset($nullableColumns[strtolower($key)]))
			{
				unset($requestBody[$key]);
			}
		}

		return $requestBody;
	}

	private function IsEntityWithEditRequiresAdmin($entity)
	{
		return in_array($entity, $this->getOpenApiSpec()->components->schemas->ExposedEntityEditRequiresAdmin->enum);
	}

	private function IsEntityWithNoListing($entity)
	{
		return in_array($entity, $this->getOpenApiSpec()->components->schemas->ExposedEntityNoListing->enum);
	}

	private function IsEntityWithNoEdit($entity)
	{
		return in_array($entity, $this->getOpenApiSpec()->components->schemas->ExposedEntityNoEdit->enum);
	}

	private function IsEntityWithNoDelete($entity)
	{
		return in_array($entity, $this->getOpenApiSpec()->components->schemas->ExposedEntityNoDelete->enum);
	}

	private function IsValidExposedEntity($entity)
	{
		return in_array($entity, $this->getOpenApiSpec()->components->schemas->ExposedEntity->enum);
	}
}
