use serde::Serialize;
use std::{env, fs, path::PathBuf, process};

#[derive(Debug, Clone, Copy, rkyv::Archive, rkyv::Serialize, rkyv::Deserialize)]
#[archive(check_bytes)]
struct G1SerdeRkyv {
    x: [u8; 48],
    y: [u8; 48],
}

#[derive(Debug, Clone, Copy, rkyv::Archive, rkyv::Serialize, rkyv::Deserialize)]
#[archive(check_bytes)]
struct G2SerdeRkyv {
    x: [u8; 96],
    y: [u8; 96],
}

#[derive(Debug, Clone, Copy, rkyv::Archive, rkyv::Serialize, rkyv::Deserialize)]
#[archive(check_bytes)]
struct PartialSigma1VerifyRkyv {
    x: G1SerdeRkyv,
    y: G1SerdeRkyv,
}

#[derive(Debug, Clone, Copy, rkyv::Archive, rkyv::Serialize, rkyv::Deserialize)]
#[archive(check_bytes)]
struct Sigma2Rkyv {
    alpha: G2SerdeRkyv,
    alpha2: G2SerdeRkyv,
    alpha3: G2SerdeRkyv,
    alpha4: G2SerdeRkyv,
    gamma: G2SerdeRkyv,
    delta: G2SerdeRkyv,
    eta: G2SerdeRkyv,
    x: G2SerdeRkyv,
    y: G2SerdeRkyv,
}

#[allow(non_snake_case)]
#[derive(Debug, rkyv::Archive, rkyv::Serialize, rkyv::Deserialize)]
#[archive(check_bytes)]
struct SigmaVerifyRkyv {
    G: G1SerdeRkyv,
    H: G2SerdeRkyv,
    sigma_1: PartialSigma1VerifyRkyv,
    sigma_2: Sigma2Rkyv,
    lagrange_KL: G1SerdeRkyv,
}

#[derive(Serialize)]
struct G1PointJson {
    x: String,
    y: String,
}

#[derive(Serialize)]
struct G2PointJson {
    x: String,
    y: String,
}

#[allow(non_snake_case)]
#[derive(Serialize)]
struct Sigma1VerifyJson {
    x: G1PointJson,
    y: G1PointJson,
}

#[derive(Serialize)]
struct Sigma2Json {
    alpha: G2PointJson,
    alpha2: G2PointJson,
    alpha3: G2PointJson,
    alpha4: G2PointJson,
    gamma: G2PointJson,
    delta: G2PointJson,
    eta: G2PointJson,
    x: G2PointJson,
    y: G2PointJson,
}

#[allow(non_snake_case)]
#[allow(non_snake_case)]
#[derive(Serialize)]
struct SigmaVerifyJson {
    G: G1PointJson,
    H: G2PointJson,
    sigma_1: Sigma1VerifyJson,
    sigma_2: Sigma2Json,
    lagrange_KL: G1PointJson,
}

fn le_bytes_to_be_hex(bytes: &[u8]) -> String {
    let mut reversed = bytes.to_vec();
    reversed.reverse();
    format!("0x{}", hex::encode(reversed))
}

fn g1_to_json(point: &ArchivedG1SerdeRkyv) -> G1PointJson {
    G1PointJson {
        x: le_bytes_to_be_hex(&point.x),
        y: le_bytes_to_be_hex(&point.y),
    }
}

fn g2_to_json(point: &ArchivedG2SerdeRkyv) -> G2PointJson {
    G2PointJson {
        x: le_bytes_to_be_hex(&point.x),
        y: le_bytes_to_be_hex(&point.y),
    }
}

fn usage_and_exit() -> ! {
    eprintln!("Usage: cargo run --manifest-path script/zk/rkyv-to-json/Cargo.toml -- <sigma_verify.rkyv> <sigma_verify.json>");
    process::exit(1);
}

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() != 3 {
        usage_and_exit();
    }

    let input_path = PathBuf::from(&args[1]);
    let output_path = PathBuf::from(&args[2]);

    let bytes = fs::read(&input_path)
        .unwrap_or_else(|err| panic!("Failed to read {}: {}", input_path.display(), err));
    let archived = rkyv::check_archived_root::<SigmaVerifyRkyv>(&bytes)
        .unwrap_or_else(|err| panic!("Invalid sigma_verify.rkyv archive at {}: {}", input_path.display(), err));

    let json = SigmaVerifyJson {
        G: g1_to_json(&archived.G),
        H: g2_to_json(&archived.H),
        sigma_1: Sigma1VerifyJson {
            x: g1_to_json(&archived.sigma_1.x),
            y: g1_to_json(&archived.sigma_1.y),
        },
        sigma_2: Sigma2Json {
            alpha: g2_to_json(&archived.sigma_2.alpha),
            alpha2: g2_to_json(&archived.sigma_2.alpha2),
            alpha3: g2_to_json(&archived.sigma_2.alpha3),
            alpha4: g2_to_json(&archived.sigma_2.alpha4),
            gamma: g2_to_json(&archived.sigma_2.gamma),
            delta: g2_to_json(&archived.sigma_2.delta),
            eta: g2_to_json(&archived.sigma_2.eta),
            x: g2_to_json(&archived.sigma_2.x),
            y: g2_to_json(&archived.sigma_2.y),
        },
        lagrange_KL: g1_to_json(&archived.lagrange_KL),
    };

    if let Some(parent) = output_path.parent() {
        fs::create_dir_all(parent)
            .unwrap_or_else(|err| panic!("Failed to create {}: {}", parent.display(), err));
    }

    let encoded = serde_json::to_string_pretty(&json).expect("Failed to serialize sigma verify JSON");
    fs::write(&output_path, format!("{encoded}\n"))
        .unwrap_or_else(|err| panic!("Failed to write {}: {}", output_path.display(), err));
}
