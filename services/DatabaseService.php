<?php

namespace Grocy\Services;

use Grocy\Services\UsersService;
use LessQL\Database;

class DatabaseService
{
	private static $DbConnection = null;
	private static $DbConnectionRaw = null;
	private static $instance = null;

	public function GetDatabaseType()
	{
		if (defined('GROCY_DATABASE_TYPE'))
		{
			return strtolower(GROCY_DATABASE_TYPE);
		}

		return 'sqlite';
	}

	public function ExecuteDbQuery(string $sql)
	{
		$pdo = $this->GetDbConnectionRaw();
		$sql = $this->NormalizeSql($sql);

		if (GROCY_MODE === 'dev')
		{
			$logFilePath = GROCY_DATAPATH . '/sql.log';
			if (file_exists($logFilePath))
			{
				file_put_contents($logFilePath, $sql . PHP_EOL, FILE_APPEND);
			}
		}

		return $pdo->query($sql);
	}

	public function ExecuteDbStatement(string $sql, array $params = null)
	{
		$pdo = $this->GetDbConnectionRaw();
		$sql = $this->NormalizeSql($sql);

		if (GROCY_MODE === 'dev')
		{
			$logFilePath = GROCY_DATAPATH . '/sql.log';
			if (file_exists($logFilePath))
			{
				file_put_contents($logFilePath, $sql . PHP_EOL, FILE_APPEND);
			}
		}

		if ($params == null)
		{
			if ($pdo->exec($sql) === false)
			{
				throw new \Exception($pdo->errorInfo());
			}
		}
		else
		{
			$sql = $this->NormalizeSql($sql);
			$cmd = $pdo->prepare($sql);
			if ($cmd->execute($params) === false)
			{
				throw new \Exception($pdo->errorInfo());
			}
		}

		return true;
	}

	public function GetDbChangedTime()
	{
		if ($this->GetDatabaseType() !== 'sqlite')
		{
			$pdo = $this->GetDbConnectionRaw();
			return (string) $pdo->query('SELECT NOW()')->fetchColumn();
		}

		return date('Y-m-d H:i:s', filemtime($this->GetDbFilePath()));
	}

	public function GetDbConnection()
	{
		if (self::$DbConnection == null)
		{
			self::$DbConnection = new Database($this->GetDbConnectionRaw());
		}

		if (GROCY_MODE === 'dev')
		{
			$logFilePath = GROCY_DATAPATH . '/sql.log';
			if (file_exists($logFilePath))
			{
				self::$DbConnection->setQueryCallback(function ($query, $params) use ($logFilePath)
				{
					file_put_contents($logFilePath, $query . ' #### ' . implode(';', $params) . PHP_EOL, FILE_APPEND);
				});
			}
		}

		return self::$DbConnection;
	}

	public function GetDbConnectionRaw()
	{
		if (self::$DbConnectionRaw == null)
		{
			if ($this->GetDatabaseType() === 'sqlite')
			{
				$pdo = new \PDO('sqlite:' . $this->GetDbFilePath());
				$pdo->setAttribute(\PDO::ATTR_ERRMODE, \PDO::ERRMODE_EXCEPTION);
				$pdo->setAttribute(\PDO::ATTR_ORACLE_NULLS, \PDO::NULL_EMPTY_STRING);
				$pdo->sqliteCreateFunction('regexp', function ($pattern, $value)
				{
					mb_regex_encoding('UTF-8');
					return (false !== mb_ereg($pattern, $value)) ? 1 : 0;
				});

				$pdo->sqliteCreateFunction('grocy_user_setting', function ($value)
				{
					$usersService = new UsersService();
					return $usersService->GetUserSetting(GROCY_USER_ID, $value);
				});

				// Unfortunately not included by default
				// https://www.sqlite.org/lang_mathfunc.html#ceil
				$pdo->sqliteCreateFunction('ceil', function ($value)
				{
					return ceil($value);
				});
			}
			else
			{
				$host = defined('GROCY_DATABASE_HOST') ? GROCY_DATABASE_HOST : 'localhost';
				$port = defined('GROCY_DATABASE_PORT') ? GROCY_DATABASE_PORT : 3306;
				$dbName = defined('GROCY_DATABASE_NAME') ? GROCY_DATABASE_NAME : 'grocy';
				$user = defined('GROCY_DATABASE_USER') ? GROCY_DATABASE_USER : 'root';
				$pass = defined('GROCY_DATABASE_PASSWORD') ? GROCY_DATABASE_PASSWORD : '';
				$dsn = "mysql:host={$host};port={$port};dbname={$dbName};charset=utf8mb4";
				$options = [
					\PDO::MYSQL_ATTR_USE_BUFFERED_QUERY => true,
					\PDO::ATTR_ERRMODE => \PDO::ERRMODE_EXCEPTION,
					\PDO::ATTR_EMULATE_PREPARES => true
				];
				$pdo = new \PDO($dsn, $user, $pass, $options);
				$pdo->setAttribute(\PDO::ATTR_ERRMODE, \PDO::ERRMODE_EXCEPTION);
				$pdo->setAttribute(\PDO::ATTR_ORACLE_NULLS, \PDO::NULL_EMPTY_STRING);
				$pdo->setAttribute(\PDO::MYSQL_ATTR_USE_BUFFERED_QUERY, true);
				$pdo->setAttribute(\PDO::ATTR_EMULATE_PREPARES, true);
			}

			self::$DbConnectionRaw = $pdo;
		}

		return self::$DbConnectionRaw;
	}

	private function NormalizeSql(string $sql): string
	{
		if ($this->GetDatabaseType() === 'sqlite')
		{
			return $sql;
		}

		$sql = preg_replace('/COLLATE\s+NOCASE/i', 'COLLATE utf8mb4_general_ci', $sql);
		$sql = preg_replace_callback(
			"/\bdate\s*\(\s*'(\d{4}-\d{2}-\d{2})'\s*,\s*'([+-]?\d+)\s+days'\s*\)/i",
			function ($matches)
			{
				$days = (int) $matches[2];
				if ($days < 0)
				{
					return "DATE_SUB('{$matches[1]}', INTERVAL " . abs($days) . " DAY)";
				}
				return "DATE_ADD('{$matches[1]}', INTERVAL {$days} DAY)";
			},
			$sql
		);
		$sql = preg_replace_callback(
			"/\bSTRFTIME\s*\(\s*'%Y-%W'\s*,\s*(DATE\s*\([^\)]+\)|[^\)]+)\s*\)/i",
			function ($matches)
			{
				return "DATE_FORMAT({$matches[1]}, '%Y-%u')";
			},
			$sql
		);
		$sql = preg_replace_callback(
			"/\bLTRIM\s*\(\s*(.*?)\s*,\s*'0'\s*\)/i",
			function ($matches)
			{
				return "TRIM(LEADING '0' FROM {$matches[1]})";
			},
			$sql
		);
		$sql = preg_replace("/\bdate\s*\(\s*'now'\s*,\s*'localtime'\s*\)/i", 'CURRENT_DATE', $sql);
		$sql = preg_replace("/\bdatetime\s*\(\s*'now'\s*,\s*'localtime'\s*\)/i", 'CURRENT_TIMESTAMP', $sql);
		$sql = preg_replace_callback(
			"/\bdate\s*\(\s*(DATE\s*\([^\)]+\)|[^\)]+?)\s*,\s*'([+-]?\d+)\s+months'\s*\)/i",
			function ($matches)
			{
				$months = (int) $matches[2];
				if ($months < 0)
				{
					return "DATE_SUB({$matches[1]}, INTERVAL " . abs($months) . " MONTH)";
				}
				return "DATE_ADD({$matches[1]}, INTERVAL {$months} MONTH)";
			},
			$sql
		);
		$sql = preg_replace_callback(
			"/\bdate\s*\(\s*(DATE\s*\([^\)]+\)|[^\)]+?)\s*,\s*'start\s+of\s+month'\s*\)/i",
			function ($matches)
			{
				return "DATE_FORMAT({$matches[1]}, '%Y-%m-01')";
			},
			$sql
		);
		$sql = preg_replace("/\bdate\s*\(\s*'now'\s*,\s*'([+-]?\d+)\s+days'\s*\)/i", 'DATE_ADD(CURRENT_DATE, INTERVAL $1 DAY)', $sql);
		$sql = preg_replace("/\bdate\s*\(\s*'now'\s*\)/i", 'CURRENT_DATE', $sql);
		$sql = preg_replace('/\bdate\s*\(\s*\)/i', 'CURRENT_DATE', $sql);
		return $sql;
	}

	public function SetDbChangedTime($dateTime)
	{
		if ($this->GetDatabaseType() !== 'sqlite')
		{
			return;
		}

		touch($this->GetDbFilePath(), strtotime($dateTime));
	}

	public static function getInstance()
	{
		if (self::$instance == null)
		{
			self::$instance = new self();
		}

		return self::$instance;
	}

	private function GetDbFilePath()
	{
		if ($this->GetDatabaseType() !== 'sqlite')
		{
			return '';
		}

		if (GROCY_MODE === 'demo' || GROCY_MODE === 'prerelease')
		{
			$dbSuffix = GROCY_DEFAULT_LOCALE;
			if (defined('GROCY_DEMO_DB_SUFFIX'))
			{
				$dbSuffix = GROCY_DEMO_DB_SUFFIX;
			}

			return GROCY_DATAPATH . '/grocy_' . $dbSuffix . '.db';
		}

		return GROCY_DATAPATH . '/grocy.db';
	}
}
