use clap::Parser;
use std::path::PathBuf;

#[derive(Parser, Debug)]
#[clap(author, version, about, long_about = None)]
struct Args {
   #[clap(short, long, value_parser, env = "AGENIX_IDENTITY")]
   identity: PathBuf,

   #[clap(short, long, value_parser, env = "AGENIX_META")]
   meta: Option<PathBuf>,

   #[clap(long, value_parser, env = "AGENIX_RULES", default_value = "./secrets.nix")]
   rules: PathBuf,

   #[clap(short, long, action)]
   force: bool,

   #[clap(short, long, action)]
   all: bool,

   #[clap(index = 1)]
   filename: Option<String>,
}

fn main() {
   let args = Args::parse();

   println!("{:?}", args);
}
