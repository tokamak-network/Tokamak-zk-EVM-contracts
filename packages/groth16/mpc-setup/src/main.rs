use std::env;
use std::future::Future;
use std::fs::File;
use std::io::{self, BufReader, Read, Seek, SeekFrom, Write};
use std::pin::Pin;
use std::path::{Path, PathBuf};

use ark_bls12_381::{Fq, G1Affine, G2Affine};
use ark_ec::AffineRepr;
use ark_ff::{BigInteger, PrimeField};
use ark_serialize::{CanonicalDeserialize, Compress, Validate};
use dusk_bls12_381::{G1Affine as DuskG1Affine, G2Affine as DuskG2Affine};
use google_drive3::api::{File as DriveFile, Permission, Scope};
use google_drive3::hyper::client::HttpConnector;
use google_drive3::hyper::Client;
use google_drive3::hyper_rustls::{HttpsConnector, HttpsConnectorBuilder};
use google_drive3::{oauth2, DriveHub};
use oauth2::authenticator_delegate::{DefaultInstalledFlowDelegate, InstalledFlowDelegate};
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

    match args.command.as_str() {
        "response-to-ptau" => convert_response_to_ptau(
            args.response
                .as_deref()
                .ok_or_else(|| "missing --response".to_string())?,
            args.power.ok_or_else(|| "missing --power".to_string())?,
            args.output
                .as_deref()
                .ok_or_else(|| "missing --output".to_string())?,
        )
        .map_err(|error| format!("response-to-ptau failed: {error}")),
        "drive-preflight" => {
            let config = args.drive_config()?;
            let archive_prefix = args
                .archive_prefix
                .as_deref()
                .ok_or_else(|| "missing --archive-prefix".to_string())?;
            drive_preflight(&config, archive_prefix)
        }
        "drive-upload-archive" => {
            let config = args.drive_config()?;
            let archive_path = args
                .archive_path
                .as_deref()
                .ok_or_else(|| "missing --archive-path".to_string())?;
            let archive_name = args
                .archive_name
                .as_deref()
                .ok_or_else(|| "missing --archive-name".to_string())?;
            drive_upload_archive(&config, archive_path, archive_name, args.result_json.as_deref())
        }
        _ => Err(format!("unsupported command: {}", args.command)),
    }
}

struct Args {
    command: String,
    response: Option<PathBuf>,
    power: Option<u32>,
    output: Option<PathBuf>,
    drive_folder_id: Option<String>,
    oauth_client_json: Option<PathBuf>,
    oauth_token_path: Option<PathBuf>,
    archive_prefix: Option<String>,
    archive_path: Option<PathBuf>,
    archive_name: Option<String>,
    result_json: Option<PathBuf>,
}

impl Args {
    fn parse<I>(mut args: I) -> Result<Self, String>
    where
        I: Iterator<Item = String>,
    {
        let command = args
            .next()
            .ok_or_else(|| "missing command".to_string())?;

        let mut parsed = Self {
            command,
            response: None,
            power: None,
            output: None,
            drive_folder_id: None,
            oauth_client_json: None,
            oauth_token_path: None,
            archive_prefix: None,
            archive_path: None,
            archive_name: None,
            result_json: None,
        };

        while let Some(flag) = args.next() {
            match flag.as_str() {
                "--response" => {
                    parsed.response = Some(
                        args.next()
                            .ok_or_else(|| "missing value for --response".to_string())?
                            .into(),
                    );
                }
                "--power" => {
                    let value = args
                        .next()
                        .ok_or_else(|| "missing value for --power".to_string())?;
                    parsed.power = Some(
                        value
                            .parse::<u32>()
                            .map_err(|_| format!("invalid power: {value}"))?,
                    );
                }
                "--output" => {
                    parsed.output = Some(
                        args.next()
                            .ok_or_else(|| "missing value for --output".to_string())?
                            .into(),
                    );
                }
                "--drive-folder-id" => {
                    parsed.drive_folder_id = Some(
                        args.next()
                            .ok_or_else(|| "missing value for --drive-folder-id".to_string())?,
                    );
                }
                "--oauth-client-json" => {
                    parsed.oauth_client_json = Some(
                        args.next()
                            .ok_or_else(|| "missing value for --oauth-client-json".to_string())?
                            .into(),
                    );
                }
                "--oauth-token-path" => {
                    parsed.oauth_token_path = Some(
                        args.next()
                            .ok_or_else(|| "missing value for --oauth-token-path".to_string())?
                            .into(),
                    );
                }
                "--archive-prefix" => {
                    parsed.archive_prefix = Some(
                        args.next()
                            .ok_or_else(|| "missing value for --archive-prefix".to_string())?,
                    );
                }
                "--archive-path" => {
                    parsed.archive_path = Some(
                        args.next()
                            .ok_or_else(|| "missing value for --archive-path".to_string())?
                            .into(),
                    );
                }
                "--archive-name" => {
                    parsed.archive_name = Some(
                        args.next()
                            .ok_or_else(|| "missing value for --archive-name".to_string())?,
                    );
                }
                "--result-json" => {
                    parsed.result_json = Some(
                        args.next()
                            .ok_or_else(|| "missing value for --result-json".to_string())?
                            .into(),
                    );
                }
                _ => return Err(format!("unsupported flag: {flag}")),
            }
        }

        Ok(parsed)
    }

    fn drive_config(&self) -> Result<DriveUploadConfig, String> {
        let folder_id = self
            .drive_folder_id
            .clone()
            .ok_or_else(|| "missing --drive-folder-id".to_string())?;
        let oauth_client_json_path = self
            .oauth_client_json
            .clone()
            .ok_or_else(|| "missing --oauth-client-json".to_string())?;
        if !oauth_client_json_path.exists() {
            return Err(format!(
                "missing OAuth client JSON file: {}",
                oauth_client_json_path.display()
            ));
        }
        if let Some(parent) = self.oauth_token_path.as_ref().and_then(|path| path.parent()) {
            std::fs::create_dir_all(parent).map_err(|error| {
                format!(
                    "cannot create OAuth token directory {}: {error}",
                    parent.display()
                )
            })?;
        }
        Ok(DriveUploadConfig {
            folder_url: drive_folder_url(&folder_id),
            folder_id,
            oauth_client_json_path,
            oauth_token_path: self.oauth_token_path.clone(),
        })
    }
}

#[derive(Clone, Debug)]
struct DriveUploadConfig {
    folder_id: String,
    folder_url: String,
    oauth_client_json_path: PathBuf,
    oauth_token_path: Option<PathBuf>,
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

fn drive_preflight(config: &DriveUploadConfig, archive_prefix: &str) -> Result<(), String> {
    let runtime = tokio::runtime::Runtime::new()
        .map_err(|error| format!("cannot create tokio runtime: {error}"))?;
    runtime.block_on(validate_drive_folder(config, archive_prefix))?;
    println!(
        "Groth16 MPC Drive preflight passed for archive prefix {archive_prefix}: {}",
        config.folder_url
    );
    Ok(())
}

fn drive_upload_archive(
    config: &DriveUploadConfig,
    archive_path: &Path,
    archive_name: &str,
    result_json: Option<&Path>,
) -> Result<(), String> {
    let archive_path = archive_path
        .canonicalize()
        .map_err(|error| format!("cannot resolve archive path {}: {error}", archive_path.display()))?;
    let runtime = tokio::runtime::Runtime::new()
        .map_err(|error| format!("cannot create tokio runtime: {error}"))?;
    let download_url = runtime.block_on(upload_drive_archive(config, &archive_path, archive_name))?;
    let payload = serde_json::json!({
        "folder_url": config.folder_url,
        "archive_name": archive_name,
        "zkey_download_url": download_url,
    });
    if let Some(result_json) = result_json {
        if let Some(parent) = result_json.parent() {
            std::fs::create_dir_all(parent).map_err(|error| {
                format!("cannot create result JSON directory {}: {error}", parent.display())
            })?;
        }
        std::fs::write(result_json, serde_json::to_vec_pretty(&payload).unwrap())
            .map_err(|error| format!("cannot write result JSON {}: {error}", result_json.display()))?;
    } else {
        println!("{payload}");
    }
    Ok(())
}

fn drive_folder_url(folder_id: &str) -> String {
    format!("https://drive.google.com/drive/folders/{folder_id}")
}

async fn validate_drive_folder(
    config: &DriveUploadConfig,
    archive_prefix: &str,
) -> Result<(), String> {
    let hub = build_drive_hub(config).await?;
    let (_, folder) = hub
        .files()
        .get(&config.folder_id)
        .param("fields", "id,mimeType,capabilities(canAddChildren)")
        .supports_all_drives(true)
        .add_scope(Scope::Full)
        .doit()
        .await
        .map_err(|error| format!("drive folder lookup failed: {error}"))?;

    if folder.mime_type.as_deref() != Some("application/vnd.google-apps.folder") {
        return Err(format!(
            "drive folder id {} does not resolve to a Google Drive folder",
            config.folder_id
        ));
    }

    let can_add_children = folder
        .capabilities
        .as_ref()
        .and_then(|capabilities| capabilities.can_add_children)
        .unwrap_or(false);
    if !can_add_children {
        return Err(format!(
            "authenticated Google Drive user cannot upload into drive folder {}",
            config.folder_id
        ));
    }

    let list_query = format!(
        "'{}' in parents and trashed = false and mimeType = 'application/zip'",
        config.folder_id
    );
    let (_, listing) = hub
        .files()
        .list()
        .q(&list_query)
        .param("fields", "files(id,name)")
        .page_size(100)
        .supports_all_drives(true)
        .include_items_from_all_drives(true)
        .add_scope(Scope::Full)
        .doit()
        .await
        .map_err(|error| format!("drive archive listing failed: {error}"))?;
    let existing_names = listing
        .files
        .unwrap_or_default()
        .into_iter()
        .filter_map(|file| file.name)
        .filter(|name| name.starts_with(archive_prefix))
        .collect::<Vec<_>>();
    if !existing_names.is_empty() {
        return Err(format!(
            "drive folder {} already contains Groth16 zkey archive(s) for this package version: {}; bump the package version before publishing again",
            config.folder_id,
            existing_names.join(", ")
        ));
    }

    Ok(())
}

async fn upload_drive_archive(
    config: &DriveUploadConfig,
    archive_path: &Path,
    archive_name: &str,
) -> Result<String, String> {
    let hub = build_drive_hub(config).await?;
    let metadata = DriveFile {
        name: Some(archive_name.to_string()),
        mime_type: Some("application/zip".to_string()),
        parents: Some(vec![config.folder_id.clone()]),
        ..Default::default()
    };
    let file = File::open(archive_path)
        .map_err(|error| format!("cannot open archive {}: {error}", archive_path.display()))?;
    let (_, uploaded_file) = hub
        .files()
        .create(metadata)
        .supports_all_drives(true)
        .add_scope(Scope::Full)
        .upload(file, "application/zip".parse::<mime::Mime>().unwrap())
        .await
        .map_err(|error| format!("drive archive upload failed: {error}"))?;
    let file_id = uploaded_file
        .id
        .ok_or_else(|| format!("drive upload for {archive_name} succeeded without returning a file id"))?;

    configure_public_archive_access(&hub, &file_id, archive_name).await?;
    Ok(format!(
        "https://drive.google.com/uc?id={file_id}&export=download"
    ))
}

async fn configure_public_archive_access(
    hub: &DriveHub<HttpsConnector<HttpConnector>>,
    file_id: &str,
    archive_name: &str,
) -> Result<(), String> {
    let permission = Permission {
        type_: Some("anyone".to_string()),
        role: Some("reader".to_string()),
        allow_file_discovery: Some(false),
        ..Default::default()
    };
    hub.permissions()
        .create(permission, file_id)
        .supports_all_drives(true)
        .add_scope(Scope::Full)
        .doit()
        .await
        .map_err(|error| {
            format!(
                "uploaded archive {archive_name} but failed to grant anyone-with-link viewer access: {error}"
            )
        })?;

    let file_metadata = DriveFile {
        copy_requires_writer_permission: Some(false),
        ..Default::default()
    };
    hub.files()
        .update(file_metadata, file_id)
        .supports_all_drives(true)
        .add_scope(Scope::Full)
        .doit_without_upload()
        .await
        .map_err(|error| {
            format!(
                "uploaded archive {archive_name} but failed to allow viewers to download, print, and copy it: {error}"
            )
        })?;

    Ok(())
}

#[derive(Copy, Clone)]
struct DriveOauthBrowserDelegate;

impl InstalledFlowDelegate for DriveOauthBrowserDelegate {
    fn present_user_url<'a>(
        &'a self,
        url: &'a str,
        need_code: bool,
    ) -> Pin<Box<dyn Future<Output = Result<String, String>> + Send + 'a>> {
        Box::pin(async move {
            if webbrowser::open(url).is_ok() {
                println!("Opened a browser window for Google Drive login.");
            }
            let delegate = DefaultInstalledFlowDelegate;
            delegate.present_user_url(url, need_code).await
        })
    }
}

async fn build_drive_hub(
    config: &DriveUploadConfig,
) -> Result<DriveHub<HttpsConnector<HttpConnector>>, String> {
    let _ = dotenvy::dotenv();
    let app_secret = oauth2::read_application_secret(&config.oauth_client_json_path)
        .await
        .map_err(|error| {
            format!(
                "cannot read OAuth client JSON from {}: {error}",
                config.oauth_client_json_path.display()
            )
        })?;
    let mut auth_builder = oauth2::InstalledFlowAuthenticator::builder(
        app_secret,
        oauth2::InstalledFlowReturnMethod::HTTPRedirect,
    )
    .flow_delegate(Box::new(DriveOauthBrowserDelegate));
    if let Some(token_path) = &config.oauth_token_path {
        auth_builder = auth_builder.persist_tokens_to_disk(token_path);
    }
    let auth = auth_builder
        .build()
        .await
        .map_err(|error| format!("cannot build Google Drive OAuth authenticator: {error}"))?;
    let https = HttpsConnectorBuilder::new()
        .with_native_roots()
        .map_err(|error| format!("cannot load native root certificates: {error}"))?
        .https_or_http()
        .enable_http1()
        .build();
    let client = Client::builder().build(https);
    Ok(DriveHub::new(client, auth))
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
