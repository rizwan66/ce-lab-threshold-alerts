import multiprocessing
import time

def busy_loop():
    while True:
        x = 0
        for i in range(10000000):
            x += i

if __name__ == '__main__':
    # Use all CPU cores
    processes = []
    for _ in range(multiprocessing.cpu_count()):
        p = multiprocessing.Process(target=busy_loop)
        p.start()
        processes.append(p)

    print(f"Started {len(processes)} CPU stress processes. Running for 15 minutes...")

    # Run for 15 minutes
    time.sleep(900)

    # Stop processes
    for p in processes:
        p.terminate()

    print("Stress test complete.")
