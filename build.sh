#!/usr/bin/env bash

DOWNLOAD_DIR=download
DECODE_DIR=decode
DIST_DIR=dist
SIGN_KS=sign.jks
APP_DEBUG_FILE=app-debug.apk
APP_DEBUG_DOWNLOAD_URL=https://github.com/brandonmathewp/Android-Mod-Menu-BNM/releases/latest/download/${APP_DEBUG_FILE}

declare -A apps
mkdir -p $DOWNLOAD_DIR

ks_pass=${SIGN_KS_PASS}

# Function to check if a command exists
check_command() {
  while [ "$#" -gt 0 ]; do
    if ! command -v "$1" >/dev/null 2>&1; then
      echo "$1 is not installed. Please install it to proceed."
      exit 1
    fi
    shift
  done
}

check_command curl apktool apksigner

if [[ ! -f build.csv ]]; then
  echo "Error: build.csv not found."
  exit 1
fi

# Load CSV, skip header, and sanitize CRLF line endings
{
  read 
  while IFS=, read -r col1 col2 col3 || [ -n "$col1" ]; do
    col3=$(echo "$col3" | tr -d '\r') 
    if [[ -n "$col1" ]]; then
      apps["$col1"]="$col1,$col2,$col3"
    fi
  done
} < build.csv

usage() {
  cat << EOF
Usage: $0 [-p <password>] <app_name>

Available apps: $(IFS="|"; echo "${!apps[*]}")

OPTIONS:
  -p  keystore password(env: SIGN_KS_PASS)
  -h  Show this help message

Example:
  $0 -p pass xphero
EOF
  exit 1
}

# Process options:
while getopts ":hp:" opt; do
  case $opt in
    h) usage ;;
    p) ks_pass=$OPTARG ;;
    :) echo "Error: Option -$OPTARG requires an argument." >&2; usage ;;
    \?) echo "Error: Invalid option: -$OPTARG" >&2; usage ;;
  esac
done

shift $((OPTIND-1))

if [[ -z "$ks_pass" || -z "$1" ]]; then
  usage
fi

IFS=, read -r app_name app_activity app_download <<< "${apps[$1]}"

if [[ -z "$app_name" ]]; then
  echo "Error: App '$1' not found in build.csv"
  usage
fi

echo -e "Downloading ${APP_DEBUG_FILE}..."
if [[ ! -f ${APP_DEBUG_FILE} ]]; then
  curl -L $APP_DEBUG_DOWNLOAD_URL -o $APP_DEBUG_FILE
else
  echo -e "Exist ${APP_DEBUG_FILE}, skip download."
fi

echo -e "\nDownloading latest ${app_name}..."
download_url="${app_download}${app_name}.apk"
gameFile="${app_name}.apk"
downloadFile="${DOWNLOAD_DIR}/${gameFile}"

if [[ ! -f ${downloadFile} ]]; then
  curl -L $download_url -o $downloadFile
  if [ $? -ne 0 ]; then
    echo -e "Cannot download ${app_name} from ${download_url}, try again." >&2
    exit 1
  fi
else
  echo -e "Exist $downloadFile, skip download."
fi

appDebugOutput=$DECODE_DIR/${APP_DEBUG_FILE%.*}
echo -e "\nDecoding ${APP_DEBUG_FILE} to ${appDebugOutput}..."
apktool d -f $APP_DEBUG_FILE -o $appDebugOutput

if [ $? -ne 0 ]; then
  echo -e "Cannot decode ${APP_DEBUG_FILE}, try again." >&2
  exit 1
fi

gameOutput=$DECODE_DIR/${gameFile%.*}
echo -e "\nDecoding ${gameFile} to ${gameOutput}..."
apktool d -f $downloadFile -o ${gameOutput}

if [ $? -ne 0 ]; then
  echo -e "Cannot decode ${gameFile}, try again." >&2
  exit 1
fi

echo -e "\nUpdate ${gameOutput}..."
libName=lib${app_name}.so
echo -e "Copy ${libName} to libModBNM.so"
find $gameOutput/lib/* -maxdepth 0 ! -name "arm64-v8a" -exec rm -rf '{}' +
cp $appDebugOutput/lib/arm64-v8a/${libName} $gameOutput/lib/arm64-v8a/libModBNM.so

echo -e "Copy smali_classes to ${gameOutput}"
cp -r $appDebugOutput/smali_classes* $gameOutput
gameActivityFile=$gameOutput/smali/${app_activity//./\/}.smali
echo -e "Edit ${gameActivityFile}"

if [[ "$OSTYPE" == "linux-gnu" || "$OSTYPE" == "linux-android" ]]; then
  sed -i '/.method protected onCreate/a\
  invoke-static {p0}, Lcom/android/support/Main;->start(Landroid/content/Context;)V' $gameActivityFile
else
  sed -i '' '/.method protected onCreate/a\
  invoke-static {p0}, Lcom/android/support/Main;->start(Landroid/content/Context;)V' $gameActivityFile
fi

if [ $? -ne 0 ]; then
  echo -e "Cannot replace ${app_activity}, try again." >&2
  exit 1
fi

echo -e "\nBuild and Sign ${gameFile}..."
apktool b -f ${gameOutput}

if [ $? -ne 0 ]; then
  echo -e "Cannot build ${gameFile}, try again." >&2
  exit 1
fi

gameDistFile=${gameOutput}/dist/${gameFile}
signOutFile=${DIST_DIR}/${gameFile}
mkdir -p ${DIST_DIR}

apksigner sign --ks ${SIGN_KS} --ks-pass "pass:${ks_pass}" --v4-signing-enabled false --out ${signOutFile} ${gameDistFile}

echo -e "\nClear ${DECODE_DIR} dir..."
rm -rf $DECODE_DIR

echo -e "\nSuccess build ${signOutFile}"
