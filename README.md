# Compute Engine web app for demos

## Description

This project is a demo application designed to showcase the capabilities of Google Compute Engine. It provides a simple web interface to monitor and control a simulated virtual machine's status.

The application allows you to:

* Toggle the CPU load between High and Low.
* Toggle the health status between Healthy and Unhealthy.
* See the uptime of the application.

## Setup

`
gcloud compute instances create app-$(date +%Y%m%d-%H%M%S) \
 --zone=us-central1-c --machine-type=e2-medium \
 --image-family=debian-12 --image-project=debian-cloud \
 --tags=http-server --metadata=startup-script='#!/bin/bash
apt-get update -y
apt-get install -y python3 python3-pip git python3-venv
git clone https://github.com/epnasis/gce-demo.git /var/www/app
cd /var/www/app
python3 -m venv venv
source venv/bin/activate
pip3 install -r requirements.txt
python3 app.py'
`

1.  **Prerequisites:**
    * Python 3.6 or later
    * Git

2.  **Clone the repository:**

    ```bash
    git clone [https://github.com/your-username/your-repository-name.git](https://github.com/your-username/your-repository-name.git)
    cd your-repository-name
    ```

3.  **Set up a virtual environment (recommended):**

    ```bash
    python3 -m venv venv
    source venv/bin/activate  # On Linux/macOS
    venv\Scripts\activate  # On Windows
    ```

4.  **Install dependencies:**

    ```bash
    pip install -r requirements.txt
    ```

5.  **Run the application:**

    ```bash
    flask run --host=0.0.0.0 --port=80
    ```

6.  **Access the application:** Open your web browser and go to `http://your-server-ip:80` or `http://localhost:80` if you are running it locally.

## Code Structure

* `app.py`:  The main Flask application file.  Defines the routes, logic for toggling CPU load and health, and the health check endpoint.
* `index.html`:  The HTML template for the main web page.  Displays the VM status, controls, and uptime.
* `style.css`:  The CSS stylesheet for the web page.  Provides the visual styling.
* `logo.png`:  The Google Cloud logo image.
* `.gitignore`: Specifies intentionally untracked files that Git should ignore.

## Endpoints

* `/`:  The main web page.
* `/toggle_cpu`:  A POST endpoint to toggle the VM's CPU load.
* `/toggle_health`:  A POST endpoint to toggle the VM's health status.
* `/healthz`: A health check endpoint that returns "OK" with a 200 status code if the application is healthy, and "Unhealthy" with a 500 status code otherwise.

## Contributing

1.  Fork the repository.
2.  Create a new branch for your feature or bug fix.
3.  Make your changes.
4.  Commit your changes and push them to your fork.
5.  Submit a pull request.

## License

[Specify the license for your project]

## Author

[Your Name or Organization]
