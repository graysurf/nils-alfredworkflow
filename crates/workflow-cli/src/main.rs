use clap::Parser;

#[derive(Debug, Parser)]
#[command(author, version, about = "Shared Alfred workflow CLI")]
struct Cli {
    /// Input query from Alfred Script Filter.
    #[arg(long, short, default_value = "")]
    query: String,
}

fn main() {
    let cli = Cli::parse();
    let feedback = workflow_common::build_feedback(&cli.query);

    match feedback.to_json() {
        Ok(json) => println!("{json}"),
        Err(err) => {
            eprintln!("error: failed to serialize Alfred feedback: {err}");
            std::process::exit(1);
        }
    }
}
