from flask import Flask, render_template, request, jsonify
import datetime
import time
import threading
import os
import multiprocessing
import socket

app = Flask(__name__)

# Initial states (now global variables, no need for shared state)
vm_cpu_load = False
vm_healthy = True
start_time = time.time()
cpu_load_processes = []  # To store the CPU load processes
NUM_CPU_CORES = multiprocessing.cpu_count()
hostname = socket.gethostname()

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
    print(f"CPU load process started in PID: {os.getpid()}")  #debug
    while vm_cpu_load:
        x = 123456789 * 987654321
        x = x // 2
        x = x + 10000
        #time.sleep(0.01)  # Add a small sleep to reduce impact somewhat.  Removed
    print(f"CPU load process stopped in PID: {os.getpid()}")  #debug

def start_cpu_load():
    """Starts generating CPU load in separate processes."""
    global cpu_load_processes, vm_cpu_load
    if not cpu_load_processes:
        vm_cpu_load = True
        num_processes = int(NUM_CPU_CORES * 0.9)  # Use 90% of CPU cores
        for _ in range(num_processes):
            process = multiprocessing.Process(target=waste_cpu)
            process.daemon = True
            cpu_load_processes.append(process)
            process.start()
        print(f"Starting CPU load with {num_processes} processes...")
    else:
        print("CPU load already running...")

def stop_cpu_load():
    """Stops the CPU load generation."""
    global vm_cpu_load, cpu_load_processes
    vm_cpu_load = False  # Signal the processes to stop
    for process in cpu_load_processes:
        process.join()  # Wait for the process to finish
    cpu_load_processes = []
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
                           uptime=uptime,
                           hostname=hostname)

@app.route('/api/toggle_cpu', methods=['POST'])
def api_toggle_cpu():
    """Toggles the CPU load status (simulated)."""
    global vm_cpu_load
    vm_cpu_load = not vm_cpu_load
    if vm_cpu_load:
        start_cpu_load()
    else:
        stop_cpu_load()
    return jsonify({'vm_cpu_load': vm_cpu_load})

@app.route('/api/toggle_health', methods=['POST'])
def api_toggle_health():
    """Toggles the VM health status (simulated)."""
    global vm_healthy
    vm_healthy = not vm_healthy
    return jsonify({'vm_healthy': vm_healthy})

@app.route('/api/uptime')
def api_uptime():
    """Returns the uptime and load time as JSON."""
    timestamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    uptime = get_uptime()
    hostname = socket.gethostname()
    return jsonify({'uptime': uptime, 'loadTime': timestamp, 'hostname': hostname})

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
