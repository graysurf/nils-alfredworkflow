use chrono::{DateTime, Utc};
use clap::{Parser, Subcommand};

use market_cli::{
    config::RuntimeConfig,
    error::AppError,
    expression,
    model::{MarketKind, MarketRequest},
    providers::{HttpProviders, ProviderApi},
    service,
};

#[derive(Debug, Parser)]
#[command(author, version, about = "FX + crypto market data CLI")]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Debug, Subcommand)]
enum Commands {
    /// Query fiat exchange rate (Frankfurter).
    Fx {
        #[arg(long)]
        base: String,
        #[arg(long)]
        quote: String,
        #[arg(long)]
        amount: String,
    },
    /// Query crypto spot price (Coinbase with Kraken fallback).
    Crypto {
        #[arg(long)]
        base: String,
        #[arg(long)]
        quote: String,
        #[arg(long)]
        amount: String,
    },
    /// Evaluate market expressions and return Alfred Script Filter JSON.
    Expr {
        #[arg(long)]
        query: String,
        #[arg(long, default_value = "USD")]
        default_fiat: String,
    },
}

fn main() {
    let cli = Cli::parse();
    match run(cli) {
        Ok(output) => {
            println!("{output}");
        }
        Err(error) => {
            eprintln!("error: {}", error.message);
            std::process::exit(error.exit_code());
        }
    }
}

fn run(cli: Cli) -> Result<String, AppError> {
    let config = RuntimeConfig::from_env();
    let providers = HttpProviders::new().map_err(|error| AppError::runtime(error.to_string()))?;
    run_with(cli, &config, &providers, Utc::now)
}

fn run_with<P, N>(
    cli: Cli,
    config: &RuntimeConfig,
    providers: &P,
    now_fn: N,
) -> Result<String, AppError>
where
    P: ProviderApi,
    N: Fn() -> DateTime<Utc> + Copy,
{
    match cli.command {
        Commands::Fx {
            base,
            quote,
            amount,
        } => run_market_command(
            config,
            providers,
            now_fn,
            MarketKind::Fx,
            &base,
            &quote,
            &amount,
        ),
        Commands::Crypto {
            base,
            quote,
            amount,
        } => run_market_command(
            config,
            providers,
            now_fn,
            MarketKind::Crypto,
            &base,
            &quote,
            &amount,
        ),
        Commands::Expr {
            query,
            default_fiat,
        } => {
            let feedback =
                expression::evaluate_query(config, providers, now_fn, &query, &default_fiat)?;
            feedback.to_json().map_err(|error| {
                AppError::runtime(format!("failed to serialize Alfred feedback: {error}"))
            })
        }
    }
}

fn run_market_command<P, N>(
    config: &RuntimeConfig,
    providers: &P,
    now_fn: N,
    kind: MarketKind,
    base: &str,
    quote: &str,
    amount: &str,
) -> Result<String, AppError>
where
    P: ProviderApi,
    N: Fn() -> DateTime<Utc>,
{
    let request = MarketRequest::new(kind, base, quote, amount).map_err(AppError::from)?;
    let output = service::resolve_market(config, providers, now_fn, &request)?;
    serde_json::to_string(&output)
        .map_err(|error| AppError::runtime(format!("failed to serialize output: {error}")))
}

#[cfg(test)]
mod tests {
    use chrono::TimeZone;
    use market_cli::{model::MarketQuote, providers::ProviderError};
    use serde_json::Value;

    use super::*;

    struct FakeProviders {
        fx_result: Result<MarketQuote, ProviderError>,
        crypto_coinbase_result: Result<MarketQuote, ProviderError>,
        crypto_kraken_result: Result<MarketQuote, ProviderError>,
    }

    impl FakeProviders {
        fn ok() -> Self {
            let now = Utc
                .with_ymd_and_hms(2026, 2, 10, 12, 0, 0)
                .single()
                .expect("time");
            Self {
                fx_result: Ok(MarketQuote::new(
                    "frankfurter",
                    rust_decimal::Decimal::new(321, 1),
                    now,
                )),
                crypto_coinbase_result: Ok(MarketQuote::new(
                    "coinbase",
                    rust_decimal::Decimal::new(670001, 1),
                    now,
                )),
                crypto_kraken_result: Ok(MarketQuote::new(
                    "kraken",
                    rust_decimal::Decimal::new(670000, 1),
                    now,
                )),
            }
        }
    }

    impl ProviderApi for FakeProviders {
        fn fetch_fx_rate(&self, _base: &str, _quote: &str) -> Result<MarketQuote, ProviderError> {
            self.fx_result.clone()
        }

        fn fetch_crypto_coinbase(
            &self,
            _base: &str,
            _quote: &str,
        ) -> Result<MarketQuote, ProviderError> {
            self.crypto_coinbase_result.clone()
        }

        fn fetch_crypto_kraken(
            &self,
            _base: &str,
            _quote: &str,
        ) -> Result<MarketQuote, ProviderError> {
            self.crypto_kraken_result.clone()
        }
    }

    fn config_in_tempdir() -> RuntimeConfig {
        RuntimeConfig {
            cache_dir: tempfile::tempdir().expect("tempdir").path().to_path_buf(),
        }
    }

    fn fixed_now() -> DateTime<Utc> {
        Utc.with_ymd_and_hms(2026, 2, 10, 12, 5, 0)
            .single()
            .expect("time")
    }

    #[test]
    fn main_outputs_fx_json_contract() {
        let cli = Cli::parse_from([
            "market-cli",
            "fx",
            "--base",
            "USD",
            "--quote",
            "TWD",
            "--amount",
            "100",
        ]);

        let output = run_with(cli, &config_in_tempdir(), &FakeProviders::ok(), fixed_now)
            .expect("fx should pass");
        let json: Value = serde_json::from_str(&output).expect("json");

        assert_eq!(json.get("kind").and_then(Value::as_str), Some("fx"));
        assert_eq!(json.get("base").and_then(Value::as_str), Some("USD"));
        assert_eq!(json.get("quote").and_then(Value::as_str), Some("TWD"));
        assert!(json.get("cache").is_some());
    }

    #[test]
    fn main_outputs_crypto_json_contract() {
        let cli = Cli::parse_from([
            "market-cli",
            "crypto",
            "--base",
            "BTC",
            "--quote",
            "USD",
            "--amount",
            "0.5",
        ]);

        let output = run_with(cli, &config_in_tempdir(), &FakeProviders::ok(), fixed_now)
            .expect("crypto should pass");
        let json: Value = serde_json::from_str(&output).expect("json");

        assert_eq!(json.get("kind").and_then(Value::as_str), Some("crypto"));
        assert_eq!(
            json.get("provider").and_then(Value::as_str),
            Some("coinbase")
        );
        assert!(json.get("converted").is_some());
    }

    #[test]
    fn main_maps_invalid_symbols_to_user_error() {
        let cli = Cli::parse_from([
            "market-cli",
            "fx",
            "--base",
            "USDT",
            "--quote",
            "TWD",
            "--amount",
            "100",
        ]);

        let err = run_with(cli, &config_in_tempdir(), &FakeProviders::ok(), fixed_now)
            .expect_err("must fail");
        assert_eq!(err.kind, market_cli::error::ErrorKind::User);
        assert_eq!(err.exit_code(), 2);
    }

    #[test]
    fn main_maps_runtime_provider_failure() {
        let cli = Cli::parse_from([
            "market-cli",
            "crypto",
            "--base",
            "BTC",
            "--quote",
            "USD",
            "--amount",
            "1",
        ]);

        let providers = FakeProviders {
            crypto_coinbase_result: Err(ProviderError::Transport("timeout".to_string())),
            crypto_kraken_result: Err(ProviderError::Http {
                status: 503,
                message: "down".to_string(),
            }),
            ..FakeProviders::ok()
        };

        let err =
            run_with(cli, &config_in_tempdir(), &providers, fixed_now).expect_err("must fail");
        assert_eq!(err.kind, market_cli::error::ErrorKind::Runtime);
        assert_eq!(err.exit_code(), 1);
    }

    #[test]
    fn main_outputs_expr_alfred_json_contract() {
        let cli = Cli::parse_from(["market-cli", "expr", "--query", "1+5"]);
        let output = run_with(cli, &config_in_tempdir(), &FakeProviders::ok(), fixed_now)
            .expect("expr should pass");
        let json: Value = serde_json::from_str(&output).expect("json");

        let items = json
            .get("items")
            .and_then(Value::as_array)
            .expect("items should be array");
        assert_eq!(items.len(), 1);
        assert_eq!(items[0].get("title").and_then(Value::as_str), Some("6"));
    }

    #[test]
    fn main_maps_expr_syntax_error_to_user_error() {
        let cli = Cli::parse_from(["market-cli", "expr", "--query", "2 btc + 5"]);
        let err = run_with(cli, &config_in_tempdir(), &FakeProviders::ok(), fixed_now)
            .expect_err("must fail");

        assert_eq!(err.kind, market_cli::error::ErrorKind::User);
        assert_eq!(err.exit_code(), 2);
    }

    #[test]
    fn main_help_flag_is_supported() {
        let help = Cli::try_parse_from(["market-cli", "--help"]).expect_err("help");
        assert_eq!(help.kind(), clap::error::ErrorKind::DisplayHelp);
    }
}
