use clap::Parser;
use std::{path::PathBuf, process};

#[derive(Parser, Debug)]
#[clap(author, version, about, long_about = None)]
struct Args {
    #[clap(short, long, value_parser, env = "AGENIX_IDENTITY")]
    identity: PathBuf,

    #[clap(short, long, value_parser, env = "AGENIX_META")]
    meta: Option<PathBuf>,

    #[clap(
        long,
        value_parser,
        env = "AGENIX_RULES",
        default_value = "./secrets.nix"
    )]
    rules: PathBuf,

    #[clap(short, long, action)]
    force: bool,

    #[clap(short, long, action)]
    all: bool,

    #[clap(index = 1)]
    filename: Option<PathBuf>,
}

fn main() {
    let args = Args::parse();

    if !args.all && args.filename.is_none() {
        eprintln!("Error: Filename must be provided if not using --all option.");
        process::exit(1);
    }
    if args.all && !args.filename.is_none() {
        eprintln!("Error: Filename and --all option can't be used together.");
        process::exit(1);
    }
    if args.all && args.force {
        eprintln!("Error: The --all and --force options are mutually exclusive.");
        process::exit(1);
    }

    println!("{:?}", args);
}
