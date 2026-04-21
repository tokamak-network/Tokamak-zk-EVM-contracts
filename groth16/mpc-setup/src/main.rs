use std::env;
use std::fs::File;
use std::io::{self, BufReader, Read, Seek, SeekFrom, Write};
use std::path::{Path, PathBuf};

use ark_bls12_381::{Fq, G1Affine, G2Affine};
use ark_ec::AffineRepr;
use ark_ff::{BigInteger, PrimeField};
use ark_serialize::{CanonicalDeserialize, Compress, Validate};
use dusk_bls12_381::{G1Affine as DuskG1Affine, G2Affine as DuskG2Affine};
use num_bigint::BigUint;

const FILE_MAX_POWER: u32 = 21;
const FIELD_BYTES: usize = 48;
const G1_COMPRESSED_BYTES: usize = 48;
const G2_COMPRESSED_BYTES: usize = 96;
const G1_AFFINE_LEM_BYTES: usize = FIELD_BYTES * 2;
const G2_AFFINE_LEM_BYTES: usize = FIELD_BYTES * 4;
const RESPONSE_HASH_BYTES: usize = 64;

fn main() {
    if let Err(error) = run() {
        eprintln!("{error}");
        std::process::exit(1);
    }
}

fn run() -> Result<(), String> {
    let args = Args::parse(env::args().skip(1))?;

    if args.command != "response-to-ptau" {
        return Err(format!("unsupported command: {}", args.command));
    }

    convert_response_to_ptau(&args.response, args.power, &args.output)
        .map_err(|error| format!("response-to-ptau failed: {error}"))
}

struct Args {
    command: String,
    response: PathBuf,
    power: u32,
    output: PathBuf,
}

impl Args {
    fn parse<I>(mut args: I) -> Result<Self, String>
    where
        I: Iterator<Item = String>,
    {
        let command = args
            .next()
            .ok_or_else(|| "missing command".to_string())?;

        let mut response = None;
        let mut power = None;
        let mut output = None;

        while let Some(flag) = args.next() {
            match flag.as_str() {
                "--response" => {
                    response = Some(
                        args.next()
                            .ok_or_else(|| "missing value for --response".to_string())?
                            .into(),
                    );
                }
                "--power" => {
                    let value = args
                        .next()
                        .ok_or_else(|| "missing value for --power".to_string())?;
                    power = Some(
                        value
                            .parse::<u32>()
                            .map_err(|_| format!("invalid power: {value}"))?,
                    );
                }
                "--output" => {
                    output = Some(
                        args.next()
                            .ok_or_else(|| "missing value for --output".to_string())?
                            .into(),
                    );
                }
                _ => return Err(format!("unsupported flag: {flag}")),
            }
        }

        let response = response.ok_or_else(|| "missing --response".to_string())?;
        let power = power.ok_or_else(|| "missing --power".to_string())?;
        let output = output.ok_or_else(|| "missing --output".to_string())?;

        Ok(Self {
            command,
            response,
            power,
            output,
        })
    }
}

fn convert_response_to_ptau(response_path: &Path, power: u32, output_path: &Path) -> io::Result<()> {
    if power > FILE_MAX_POWER {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            format!(
                "requested power {power} exceeds response maximum {FILE_MAX_POWER}"
            ),
        ));
    }

    let expected_size = RESPONSE_HASH_BYTES as u64
        + (tau_g1_points(FILE_MAX_POWER) as u64) * G1_COMPRESSED_BYTES as u64
        + (tau_points(FILE_MAX_POWER) as u64) * G2_COMPRESSED_BYTES as u64
        + (tau_points(FILE_MAX_POWER) as u64) * G1_COMPRESSED_BYTES as u64
        + (tau_points(FILE_MAX_POWER) as u64) * G1_COMPRESSED_BYTES as u64
        + G2_COMPRESSED_BYTES as u64
        + public_key_bytes() as u64;
    let actual_size = response_path.metadata()?.len();
    if actual_size != expected_size {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            format!("unexpected response size: expected {expected_size}, got {actual_size}"),
        ));
    }

    let mut reader = BufReader::new(File::open(response_path)?);
    let mut output = File::create(output_path)?;

    let modulus = BigUint::from_bytes_le(&Fq::MODULUS.to_bytes_le());
    let montgomery_r = (BigUint::from(1u8) << (FIELD_BYTES * 8)) % &modulus;

    write_file_header(&mut output)?;
    write_ptau_header_section(&mut output, power, FILE_MAX_POWER, &modulus)?;

    let mut previous_hash = [0u8; RESPONSE_HASH_BYTES];
    reader.read_exact(&mut previous_hash)?;

    write_g1_section(
        &mut reader,
        &mut output,
        2,
        tau_g1_points(power),
        tau_g1_points(FILE_MAX_POWER),
        &modulus,
        &montgomery_r,
        Some(G1Consistency::Generator),
    )?;
    write_g2_section(
        &mut reader,
        &mut output,
        3,
        tau_points(power),
        tau_points(FILE_MAX_POWER),
        &modulus,
        &montgomery_r,
        Some(G2Consistency::Generator),
    )?;
    write_g1_section(
        &mut reader,
        &mut output,
        4,
        tau_points(power),
        tau_points(FILE_MAX_POWER),
        &modulus,
        &montgomery_r,
        None,
    )?;
    write_g1_section(
        &mut reader,
        &mut output,
        5,
        tau_points(power),
        tau_points(FILE_MAX_POWER),
        &modulus,
        &montgomery_r,
        None,
    )?;
    write_g2_section(
        &mut reader,
        &mut output,
        6,
        1,
        1,
        &modulus,
        &montgomery_r,
        None,
    )?;
    write_empty_contributions_section(&mut output)?;

    output.flush()?;
    Ok(())
}

fn tau_points(power: u32) -> usize {
    1usize << power
}

fn tau_g1_points(power: u32) -> usize {
    (1usize << (power + 1)) - 1
}

fn public_key_bytes() -> usize {
    G1_AFFINE_LEM_BYTES * 6 + G2_AFFINE_LEM_BYTES * 3
}

fn write_file_header(file: &mut File) -> io::Result<()> {
    file.write_all(b"ptau")?;
    write_u32_le(file, 1)?;
    write_u32_le(file, 7)?;
    Ok(())
}

fn write_ptau_header_section(
    file: &mut File,
    power: u32,
    ceremony_power: u32,
    modulus: &BigUint,
) -> io::Result<()> {
    let size_pos = start_section(file, 1)?;
    write_u32_le(file, FIELD_BYTES as u32)?;
    write_padded_le(file, modulus, FIELD_BYTES)?;
    write_u32_le(file, power)?;
    write_u32_le(file, ceremony_power)?;
    finish_section(file, size_pos)
}

fn write_empty_contributions_section(file: &mut File) -> io::Result<()> {
    let size_pos = start_section(file, 7)?;
    write_u32_le(file, 0)?;
    finish_section(file, size_pos)
}

fn write_g1_section(
    reader: &mut BufReader<File>,
    output: &mut File,
    section_id: u32,
    kept_points: usize,
    total_points: usize,
    modulus: &BigUint,
    montgomery_r: &BigUint,
    consistency: Option<G1Consistency>,
) -> io::Result<()> {
    let size_pos = start_section(output, section_id)?;
    let mut compressed = [0u8; G1_COMPRESSED_BYTES];

    for index in 0..kept_points {
        reader.read_exact(&mut compressed)?;

        if index == 0 {
            if let Some(check) = consistency {
                validate_g1(&compressed, check)?;
            }
        }

        let point = G1Affine::deserialize_with_mode(
            &mut &compressed[..],
            Compress::Yes,
            Validate::No,
        )
        .map_err(deser_err)?;
        write_g1_lem(output, &point, modulus, montgomery_r)?;
    }

    skip_bytes(reader, (total_points - kept_points) * G1_COMPRESSED_BYTES)?;
    finish_section(output, size_pos)
}

fn write_g2_section(
    reader: &mut BufReader<File>,
    output: &mut File,
    section_id: u32,
    kept_points: usize,
    total_points: usize,
    modulus: &BigUint,
    montgomery_r: &BigUint,
    consistency: Option<G2Consistency>,
) -> io::Result<()> {
    let size_pos = start_section(output, section_id)?;
    let mut compressed = [0u8; G2_COMPRESSED_BYTES];

    for index in 0..kept_points {
        reader.read_exact(&mut compressed)?;

        if index == 0 {
            if let Some(check) = consistency {
                validate_g2(&compressed, check)?;
            }
        }

        let point = G2Affine::deserialize_with_mode(
            &mut &compressed[..],
            Compress::Yes,
            Validate::No,
        )
        .map_err(deser_err)?;
        write_g2_lem(output, &point, modulus, montgomery_r)?;
    }

    skip_bytes(reader, (total_points - kept_points) * G2_COMPRESSED_BYTES)?;
    finish_section(output, size_pos)
}

fn start_section(file: &mut File, section_id: u32) -> io::Result<u64> {
    write_u32_le(file, section_id)?;
    let size_pos = file.stream_position()?;
    write_u64_le(file, 0)?;
    Ok(size_pos)
}

fn finish_section(file: &mut File, size_pos: u64) -> io::Result<()> {
    let end_pos = file.stream_position()?;
    let section_size = end_pos - size_pos - 8;
    file.seek(SeekFrom::Start(size_pos))?;
    write_u64_le(file, section_size)?;
    file.seek(SeekFrom::Start(end_pos))?;
    Ok(())
}

fn skip_bytes(reader: &mut BufReader<File>, bytes: usize) -> io::Result<()> {
    reader.seek(SeekFrom::Current(bytes as i64))?;
    Ok(())
}

fn write_g1_lem(
    writer: &mut File,
    point: &G1Affine,
    modulus: &BigUint,
    montgomery_r: &BigUint,
) -> io::Result<()> {
    if point.is_zero() {
        writer.write_all(&[0u8; G1_AFFINE_LEM_BYTES])?;
        return Ok(());
    }

    write_fq_lem(writer, point.x, modulus, montgomery_r)?;
    write_fq_lem(writer, point.y, modulus, montgomery_r)?;
    Ok(())
}

fn write_g2_lem(
    writer: &mut File,
    point: &G2Affine,
    modulus: &BigUint,
    montgomery_r: &BigUint,
) -> io::Result<()> {
    if point.is_zero() {
        writer.write_all(&[0u8; G2_AFFINE_LEM_BYTES])?;
        return Ok(());
    }

    write_fq_lem(writer, point.x.c0, modulus, montgomery_r)?;
    write_fq_lem(writer, point.x.c1, modulus, montgomery_r)?;
    write_fq_lem(writer, point.y.c0, modulus, montgomery_r)?;
    write_fq_lem(writer, point.y.c1, modulus, montgomery_r)?;
    Ok(())
}

fn write_fq_lem(
    writer: &mut File,
    value: Fq,
    modulus: &BigUint,
    montgomery_r: &BigUint,
) -> io::Result<()> {
    let canonical = BigUint::from_bytes_le(&value.into_bigint().to_bytes_le());
    let montgomery = (canonical * montgomery_r) % modulus;
    write_padded_le(writer, &montgomery, FIELD_BYTES)
}

fn write_padded_le(writer: &mut File, value: &BigUint, width: usize) -> io::Result<()> {
    let mut bytes = value.to_bytes_le();
    if bytes.len() > width {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "value does not fit declared width",
        ));
    }
    bytes.resize(width, 0);
    writer.write_all(&bytes)
}

fn write_u32_le(writer: &mut File, value: u32) -> io::Result<()> {
    writer.write_all(&value.to_le_bytes())
}

fn write_u64_le(writer: &mut File, value: u64) -> io::Result<()> {
    writer.write_all(&value.to_le_bytes())
}

fn deser_err(error: ark_serialize::SerializationError) -> io::Error {
    io::Error::new(io::ErrorKind::InvalidData, error.to_string())
}

#[derive(Copy, Clone)]
enum G1Consistency {
    Generator,
}

#[derive(Copy, Clone)]
enum G2Consistency {
    Generator,
}

fn validate_g1(bytes: &[u8; G1_COMPRESSED_BYTES], check: G1Consistency) -> io::Result<()> {
    let point = DuskG1Affine::from_compressed(bytes)
        .into_option()
        .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidData, "invalid Dusk G1 point"))?;
    match check {
        G1Consistency::Generator => {
            if point != DuskG1Affine::generator() {
                return Err(io::Error::new(
                    io::ErrorKind::InvalidData,
                    "Dusk tauG1[0] is not the G1 generator",
                ));
            }
        }
    }
    Ok(())
}

fn validate_g2(bytes: &[u8; G2_COMPRESSED_BYTES], check: G2Consistency) -> io::Result<()> {
    let point = DuskG2Affine::from_compressed(bytes)
        .into_option()
        .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidData, "invalid Dusk G2 point"))?;
    match check {
        G2Consistency::Generator => {
            if point != DuskG2Affine::generator() {
                return Err(io::Error::new(
                    io::ErrorKind::InvalidData,
                    "Dusk tauG2[0] is not the G2 generator",
                ));
            }
        }
    }
    Ok(())
}
