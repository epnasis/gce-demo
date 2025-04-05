#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

# --- Configuration ---
# Region for Compute Engine resources (VM Template, default zone for VM creation example)
GCP_REGION="us-central1"
# Artifact Registry location - set to 'us' multi-region
AR_LOCATION="us"
AR_REPO_NAME="images"
DOCKER_IMAGE_NAME="gce-demo"
DOCKER_IMAGE_TAG="latest"
VM_TEMPLATE_NAME="gce-demo-cos-template"
MACHINE_TYPE="c3-standard-8"

# --- Ask for and Validate Project ID ---
PROJECT_ID="" # Initialize

if [[ -n "$1" ]]; then
  # Use the first positional argument if provided
  echo "[*] Using Project ID provided as argument: $1"
  PROJECT_ID="$1"
  # Validate the provided argument
  echo "[?] Verifying project '$PROJECT_ID'..."
  if ! gcloud projects describe "$PROJECT_ID" >/dev/null 2>&1; then
    echo "[!] Error: Project ID '$PROJECT_ID' provided as argument is invalid or inaccessible."
    exit 1 # Exit if the argument is invalid
  fi
  echo "[*] Project '$PROJECT_ID' verified."
else
  # No argument provided, ask interactively, proposing env var if set
  SUGGESTED_PROJECT_ID="${GOOGLE_CLOUD_PROJECT:-}" # Get env var or empty string

  while true; do
    if [[ -n "$SUGGESTED_PROJECT_ID" ]]; then
      # Propose the env var as default
      read -p "Enter your GCP Project ID [$SUGGESTED_PROJECT_ID]: " PROJECT_ID_INPUT
      # If user pressed Enter without typing anything, use the suggestion
      if [[ -z "$PROJECT_ID_INPUT" ]]; then
          PROJECT_ID="$SUGGESTED_PROJECT_ID"
      else
          PROJECT_ID="$PROJECT_ID_INPUT"
      fi
    else
      # No env var, just prompt normally
      read -p "Enter your GCP Project ID: " PROJECT_ID
    fi

    # Validation logic (operates on the final PROJECT_ID)
    if [[ -z "$PROJECT_ID" ]]; then
      echo "[!] Project ID cannot be empty. Please try again."
      # Reset suggestion in case it was cleared by user input
      SUGGESTED_PROJECT_ID="${GOOGLE_CLOUD_PROJECT:-}"
      continue # Loop back
    fi

    echo "[?] Verifying project '$PROJECT_ID'..."
    if gcloud projects describe "$PROJECT_ID" >/dev/null 2>&1; then
      echo "[*] Project '$PROJECT_ID' found and accessible."
      break # Exit loop, Project ID is valid
    else
      echo "[!] Error: Project '$PROJECT_ID' not found or you don't have permission to access it."
      echo "[*] Please check the Project ID and your permissions, then try again."
      PROJECT_ID="" # Clear for next loop iteration
      # Reset suggestion in case it was cleared by user input
      SUGGESTED_PROJECT_ID="${GOOGLE_CLOUD_PROJECT:-}"
    fi
  done
fi


# --- Script Start (using validated PROJECT_ID) ---
echo "[*] Proceeding with setup for project: $PROJECT_ID"
echo "[*] Compute Engine Region: $GCP_REGION"
echo "[*] Artifact Registry Location: $AR_LOCATION"

# 1. Set gcloud project context
echo "[*] Setting gcloud project to $PROJECT_ID..."
gcloud config set project $PROJECT_ID

# 2. Enable necessary Google Cloud APIs
echo "[*] Enabling required GCP APIs..."
gcloud services enable \
    compute.googleapis.com \
    artifactregistry.googleapis.com \
    iam.googleapis.com \
    serviceusage.googleapis.com \
    orgpolicy.googleapis.com \
    logging.googleapis.com \
    monitoring.googleapis.com \
    servicehealth.googleapis.com \
    --project=$PROJECT_ID

# 3. Set Project Defaults
echo "[*] Setting default region and zone metadata..."
gcloud compute project-info add-metadata --metadata google-compute-default-region=$GCP_REGION,google-compute-default-zone=${GCP_REGION}-c --project=$PROJECT_ID

echo "[*] Setting default data-protection metadata to no backups..."
gcloud compute project-info add-metadata --metadata google-compute-default-data-protection=NONE --project=$PROJECT_ID

# 4. Configure Org Policies
echo "[*] Setting org-policy to allow Serial Port Access..."
gcloud resource-manager org-policies disable-enforce compute.disableSerialPortAccess --project=$PROJECT_ID

echo "[*] Setting org-policy to allow cloud storage with public access..."
gcloud resource-manager org-policies disable-enforce storage.publicAccessPrevention --project=$PROJECT_ID

echo "[*] Setting org-policy to allow cloud storage allUsers sharing..."
FILE=org-policy-iam.yaml # Temp file for IAM policy
cat > $FILE << EOF
{
  "constraint": "constraints/iam.allowedPolicyMemberDomains",
  "listPolicy": {
    "allValues": "ALLOW"
  }
}
EOF
gcloud resource-manager org-policies set-policy $FILE --project=$PROJECT_ID
rm $FILE

echo "[*] Setting org-policy to allow External IP access for VMs..."
FILE=org-policy-ip.yaml # Temp file for IP policy
cat > $FILE << EOF
{
  "constraint": "constraints/compute.vmExternalIpAccess",
  "listPolicy": {
    "allValues": "ALLOW"
  }
}
EOF
gcloud resource-manager org-policies set-policy $FILE --project=$PROJECT_ID
rm $FILE

# 5. Network Check
echo "[?] Checking default network..."
if gcloud compute networks describe default --format="value(name)" --project=$PROJECT_ID > /dev/null 2>&1; then
  echo "[*] Default network already exists."
else
  echo "[+] Default network does not exist. Creating it..."
  gcloud compute networks create default --subnet-mode=auto --project=$PROJECT_ID
fi

# 6. Firewall Rule Check for HTTP
echo "[?] Checking firewall rule 'default-allow-http'..."
if gcloud compute firewall-rules describe default-allow-http --project=$PROJECT_ID > /dev/null 2>&1; then
  echo "[*] Firewall rule 'default-allow-http' already exists."
else
  echo "[+] Firewall rule 'default-allow-http' does not exist. Creating it..."
  # Create rule to allow TCP:80 from anywhere to instances tagged 'http-server'
  gcloud compute firewall-rules create default-allow-http \
    --project=$PROJECT_ID \
    --network=default \
    --direction=INGRESS \
    --priority=1000 \
    --allow=tcp:80 \
    --source-ranges=0.0.0.0/0 \
    --target-tags=http-server \
    --description="Allow incoming HTTP traffic (TCP port 80) from anywhere to instances tagged http-server"
fi

# 7. Firewall Rule Check for SSH
echo "[?] Checking firewall rule 'default-allow-ssh'..."
if gcloud compute firewall-rules describe default-allow-ssh --project=$PROJECT_ID > /dev/null 2>&1; then
  echo "[*] Firewall rule 'default-allow-ssh' already exists."
else
  echo "[+] Firewall rule 'default-allow-ssh' does not exist. Creating it..."
  # Create rule to allow TCP:22 from anywhere to *all* instances in the default network
  gcloud compute firewall-rules create default-allow-ssh \
    --project=$PROJECT_ID \
    --network=default \
    --direction=INGRESS \
    --priority=1000 \
    --allow=tcp:22 \
    --source-ranges=0.0.0.0/0 \
    --description="Allow incoming SSH traffic (TCP port 22) from anywhere to all instances"
    # Note: No --target-tags means it applies to all instances in the network
fi


# --- Begin App-Specific Setup ---

# 8. Create Artifact Registry repository if it doesn't exist
echo "[?] Checking Artifact Registry repository '$AR_REPO_NAME' in location '$AR_LOCATION'..."
if gcloud artifacts repositories describe "$AR_REPO_NAME" --location=$AR_LOCATION --project=$PROJECT_ID > /dev/null 2>&1; then
    echo "[*] Artifact Registry repository '$AR_REPO_NAME' already exists."
else
    echo "[+] Creating Artifact Registry repository '$AR_REPO_NAME' in location '$AR_LOCATION'..."
    gcloud artifacts repositories create "$AR_REPO_NAME" \
        --repository-format=docker \
        --location=$AR_LOCATION \
        --description="Docker repository for $DOCKER_IMAGE_NAME" \
        --project=$PROJECT_ID \
        --quiet
fi


# 9. Grant VM Service Account permissions to pull images
echo "[+] Granting Artifact Registry Reader role to default Compute Engine service account..."
# Get the default Compute Engine service account email to grant permissions to it
PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format='value(projectNumber)')
SERVICE_ACCOUNT_EMAIL="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"

# Grant the role to the service account for the specific repository
gcloud artifacts repositories add-iam-policy-binding "$AR_REPO_NAME" \
    --location=$AR_LOCATION \
    --project=$PROJECT_ID \
    --member="serviceAccount:${SERVICE_ACCOUNT_EMAIL}" \
    --role="roles/artifactregistry.reader" \
    --condition=None # Explicitly no condition needed

# --- Note on Public Access (Alternative - Use with Caution!) ---
# If you truly needed the repository to be public (less secure, generally not recommended for this):
# You would run this INSTEAD of the command above:
# gcloud artifacts repositories add-iam-policy-binding "$AR_REPO_NAME" --location=$AR_LOCATION --project=$PROJECT_ID --member="allUsers" --role="roles/artifactregistry.reader" --condition=None

# 10. Configure local Docker authentication
AR_DOCKER_HOST="${AR_LOCATION}-docker.pkg.dev"
echo "[*] Configuring local Docker authentication for ${AR_DOCKER_HOST}..."
gcloud auth configure-docker "$AR_DOCKER_HOST" --project=$PROJECT_ID

# 11. Build the Docker image locally
# Assumes Dockerfile is in the current directory (.)
FULL_IMAGE_PATH="${AR_DOCKER_HOST}/${PROJECT_ID}/${AR_REPO_NAME}/${DOCKER_IMAGE_NAME}:${DOCKER_IMAGE_TAG}"
echo "[*] Building Docker image: $FULL_IMAGE_PATH..."
docker build -t "$FULL_IMAGE_PATH" .

# 12. Push the Docker image to Artifact Registry
echo "[*] Pushing Docker image to Artifact Registry..."
docker push "$FULL_IMAGE_PATH"

# 13. Create GCE Instance Template if it doesn't exist
echo "[?] Checking GCE Instance Template '$VM_TEMPLATE_NAME'..."
if gcloud compute instance-templates describe "$VM_TEMPLATE_NAME" --project=$PROJECT_ID > /dev/null 2>&1; then
    echo "[*] GCE Instance Template '$VM_TEMPLATE_NAME' already exists."
else
    echo "[+] Creating GCE Instance Template '$VM_TEMPLATE_NAME' in region '$GCP_REGION'..."
    # Define the startup script that will run inside the VM
    # Using the specific multi-region image path ensures the correct image is run
    STARTUP_SCRIPT_CONTENT='#! /bin/bash
    IMAGE_PATH="'$FULL_IMAGE_PATH'"
    docker pull $IMAGE_PATH
    docker rm -f app || true
    docker run -d --name app -p 80:8080 --restart=always $IMAGE_PATH'

    # Create the instance template using COS, SSD, and the startup script
    # Service account was granted permissions earlier
    gcloud compute instance-templates create "$VM_TEMPLATE_NAME" \
        --project=$PROJECT_ID \
        --machine-type=$MACHINE_TYPE \
        --region=$GCP_REGION \
        --tags=http-server \
        --image-project=cos-cloud \
        --image-family=cos-stable \
        --boot-disk-size=10GB \
        --boot-disk-type=pd-ssd \
        --metadata=startup-script="$STARTUP_SCRIPT_CONTENT" \
        --labels=app=$DOCKER_IMAGE_NAME
fi

echo "--- Setup Complete! ---"
echo "[*] Project: $PROJECT_ID"
echo "[*] Artifact Registry Repo: $AR_REPO_NAME in $AR_LOCATION (multi-region)"
echo "[*] Pushed Image: $FULL_IMAGE_PATH"
echo "[*] Instance Template Created or Verified: $VM_TEMPLATE_NAME in $GCP_REGION"
echo ""
echo "[*] You can now create a VM instance from this template using the GCP Console"
echo "[*] or the following gcloud command (replace ZONE, generates dynamic name):"
echo "gcloud compute instances create \"app-\$(date +%Y%m%d-%H%M%S)\" --project=$PROJECT_ID --zone=${GCP_REGION}-a --source-instance-template=$VM_TEMPLATE_NAME"

