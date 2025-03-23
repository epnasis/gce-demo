from flask import Flask, render_template, request, jsonify
import datetime
import time
import threading
import os
import multiprocessing
import socket
import math
import sys

app = Flask(__name__)

# Initial states (now global variables, no need for shared state)
vm_cpu_load = False
vm_healthy = True
start_time = time.time()
cpu_load_processes = []  # To store the CPU load processes
NUM_CPU_CORES = multiprocessing.cpu_count()
hostname = socket.gethostname()
DEFAULT_INTERVAL = 300
DEFAULT_UTILIZATION = 90

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

def load_worker(interval, utilization):
    """Worker function to generate CPU load."""
    start_time = time.time()
    for i in range(0, int(interval)):
        while time.time() - start_time < i + utilization / 100.0:
            a = math.sqrt(64 * 64 * 64 * 64 * 64)
        time.sleep(1 - utilization / 100.0)

def generate_cpu_load(interval=DEFAULT_INTERVAL, utilization=DEFAULT_UTILIZATION):
    """
    Generate a utilization % for a duration of interval seconds.
    It checks the number of CPU cores and uses multiprocessing to run
    the generate load function on all cores in parallel.
    To generate a load, we perform an arithmetic operation for a fraction
    of a second and then sleep for the rest.
    So if you want 20% utilization, the script would run the arithmetic
    operation for 0.2 seconds and then sleep for 0.8 seconds.
    """
    global cpu_load_processes
    processes = []
    for _ in range(multiprocessing.cpu_count()):
        p = multiprocessing.Process(target=load_worker, args=(interval, utilization))
        p.daemon = True
        p.start()
        processes.append(p)
    cpu_load_processes = processes

def start_cpu_load(interval=DEFAULT_INTERVAL, utilization=DEFAULT_UTILIZATION):
    """Starts generating CPU load in separate processes."""
    global cpu_load_processes, vm_cpu_load
    if not cpu_load_processes:
        vm_cpu_load = True
        generate_cpu_load(interval, utilization)
        print(f"Starting CPU load with {len(cpu_load_processes)} processes, {utilization}% utilization for {interval} seconds...")
    else:
        print("CPU load already running...")

def stop_cpu_load():
    """Stops the CPU load generation."""
    global vm_cpu_load, cpu_load_processes
    vm_cpu_load = False  # Signal the processes to stop
    for process in cpu_load_processes:
        process.terminate()
        process.join()  # Wait for the process to finish
    cpu_load_processes = []
    print("Stopping CPU load.")

@app.route('/')
def index():
    """Renders the main page with dynamic status."""
    uptime = get_uptime()
    return render_template('index.html',
                           vm_cpu_load=vm_cpu_load,
                           vm_healthy=vm_healthy,
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
    uptime = get_uptime()
    return jsonify({'uptime': uptime, 'hostname': hostname})

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
