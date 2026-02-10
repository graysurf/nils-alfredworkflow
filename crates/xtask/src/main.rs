use anyhow::{Context, Result, anyhow};
use clap::{Args, Parser, Subcommand};
use std::process::Command;

#[derive(Debug, Parser)]
#[command(author, version, about = "Monorepo workflow task runner")]
struct Cli {
    #[command(subcommand)]
    command: TopLevelCommand,
}

#[derive(Debug, Subcommand)]
enum TopLevelCommand {
    Workflow(WorkflowArgs),
}

#[derive(Debug, Args)]
struct WorkflowArgs {
    #[command(subcommand)]
    command: WorkflowCommand,
}

#[derive(Debug, Subcommand)]
enum WorkflowCommand {
    List,
    Lint {
        #[arg(long)]
        id: Option<String>,
    },
    Test {
        #[arg(long)]
        id: Option<String>,
    },
    Pack(PackArgs),
    New {
        #[arg(long)]
        id: String,
    },
}

#[derive(Debug, Args)]
struct PackArgs {
    #[arg(long, conflicts_with = "all")]
    id: Option<String>,
    #[arg(long)]
    all: bool,
    #[arg(long)]
    install: bool,
}

fn main() {
    if let Err(err) = run() {
        eprintln!("error: {err:#}");
        std::process::exit(1);
    }
}

fn run() -> Result<()> {
    let cli = Cli::parse();

    match cli.command {
        TopLevelCommand::Workflow(workflow) => match workflow.command {
            WorkflowCommand::List => run_script("workflow-pack.sh", &["--list"]),
            WorkflowCommand::Lint { id } => {
                let mut args: Vec<&str> = Vec::new();
                if let Some(id) = id.as_deref() {
                    args.extend(["--id", id]);
                }
                run_script("workflow-lint.sh", &args)
            }
            WorkflowCommand::Test { id } => {
                let mut args: Vec<&str> = Vec::new();
                if let Some(id) = id.as_deref() {
                    args.extend(["--id", id]);
                }
                run_script("workflow-test.sh", &args)
            }
            WorkflowCommand::Pack(pack) => {
                let mut args: Vec<&str> = Vec::new();
                if pack.all {
                    args.push("--all");
                }
                if let Some(id) = pack.id.as_deref() {
                    args.extend(["--id", id]);
                }
                if pack.install {
                    args.push("--install");
                }
                if !pack.all && pack.id.is_none() {
                    return Err(anyhow!("pack requires either --id <workflow> or --all"));
                }
                run_script("workflow-pack.sh", &args)
            }
            WorkflowCommand::New { id } => run_script("workflow-new.sh", &["--id", id.as_str()]),
        },
    }
}

fn run_script(script: &str, args: &[&str]) -> Result<()> {
    let path = format!("scripts/{script}");
    let status = Command::new(&path)
        .args(args)
        .status()
        .with_context(|| format!("failed to run {path}"))?;

    if status.success() {
        Ok(())
    } else {
        Err(anyhow!("{path} exited with status {status}"))
    }
}
