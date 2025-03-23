from flask import Flask, render_template, request, jsonify
import datetime
import time
import threading
import os

app = Flask(__name__)

# Initial states
vm_cpu_load = False
vm_healthy = True
start_time = time.time()
cpu_load_thread = None  # To store the CPU load thread

def get_uptime():
    """Calculates the uptime of the application."""
    uptime_seconds = time.time() - start_time
    days = int(uptime_seconds // (24 * 3600))
    uptime_seconds %= (24 * 3600)
    hours = int(uptime_seconds // 3600)
    uptime_seconds %= 3600
    minutes = int(uptime_seconds // 60)
    seconds = int(uptime_seconds % 60)
    return f"{days} days, {hours} hours, {minutes} minutes, {seconds} seconds"

def waste_cpu():
    """
    This function consumes CPU by performing a calculation in a loop.
    It now checks the global vm_cpu_load variable to stop.
    """
    global vm_cpu_load
    print("CPU load thread started.") #debug
    while vm_cpu_load:
        x = 123456789 * 987654321
        x = x // 2
        x = x + 10000
        #time.sleep(0.01)  # Add a small sleep to reduce impact somewhat.  Removed
    print("CPU load thread stopped.") #debug

def start_cpu_load():
    """Starts generating CPU load in a separate thread."""
    global cpu_load_thread, vm_cpu_load
    if cpu_load_thread is None or not cpu_load_thread.is_alive():
        vm_cpu_load = True
        cpu_load_thread = threading.Thread(target=waste_cpu)
        cpu_load_thread.daemon = True
        cpu_load_thread.start()
        print("Starting CPU load...")
    else:
        print("CPU load already running...")

def stop_cpu_load():
    """Stops the CPU load generation."""
    global vm_cpu_load, cpu_load_thread
    vm_cpu_load = False  # Signal the thread to stop
    if cpu_load_thread is not None and cpu_load_thread.is_alive():
        cpu_load_thread.join()  # Wait for the thread to finish
    cpu_load_thread = None
    print("Stopping CPU load.")

@app.route('/')
def index():
    """Renders the main page with dynamic status."""
    timestamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    uptime = get_uptime()
    return render_template('index.html',
                           vm_cpu_load=vm_cpu_load,
                           vm_healthy=vm_healthy,
                           timestamp=timestamp,
                           uptime=uptime)

@app.route('/toggle_cpu', methods=['POST'])
def toggle_cpu():
    """Toggles the CPU load status (simulated)."""
    global vm_cpu_load
    if vm_cpu_load:
        stop_cpu_load()
    else:
        start_cpu_load()
    return jsonify({'vm_cpu_load': vm_cpu_load})

@app.route('/toggle_health', methods=['POST'])
def toggle_health():
    """Toggles the VM health status (simulated)."""
    global vm_healthy
    vm_healthy = not vm_healthy
    return jsonify({'vm_healthy': vm_healthy})

@app.route('/healthz')
def healthz():
    """Simulates a health check endpoint."""
    if vm_healthy:
        return 'OK', 200
    else:
        return 'Unhealthy', 500

if __name__ == '__main__':
    # Run the Flask app.  Make sure 'debug' is False in production.
    app.run(debug=True, host='0.0.0.0', port=80)
