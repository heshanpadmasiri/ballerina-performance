#!/usr/bin/env python
import json
import os
import subprocess
import sys
from typing import TypedDict, List, Dict

class TestGrid(TypedDict):
    heap_sizes: List[str]
    message_sizes: List[int]
    n_users: List[int]
    active_process_counts: List[int]
    instance_types: List[str]

class RunConfig(TypedDict):
    bal_installer_path: str

class TestConfig(TypedDict):
    test_configs: RunConfig
    test_grid: TestGrid

class MachineConfig(TypedDict):
    memory: int
    cpu: int
    arch: str

DEBUG = False
DIST_PATH = os.path.abspath('..')
BAL_START_SCRIPT_PATH = f'{DIST_PATH}/ballerina/ballerina-start.sh'
SCRIPT_PATH = os.path.abspath(__file__)
SCRIPT_DIR = os.path.dirname(SCRIPT_PATH)
DIST_NAME = 'ballerina-performance-distribution-1.1.1-SNAPSHOT'
DIST_ZIP_PATH = os.path.abspath(f'{DIST_PATH}/../{DIST_NAME}.tar.gz')
CLOUD_FORMATION_COMMON_PATH = f'{DIST_PATH}/cloudformation/cloudformation-common.sh'

def validate_paths():
    if not os.path.exists(DIST_ZIP_PATH):
        raise FileNotFoundError(f'{DIST_ZIP_PATH} not found')
    if not os.path.exists(DIST_PATH):
        raise FileNotFoundError(f'{DIST_PATH} not found')
    if not os.path.exists(BAL_START_SCRIPT_PATH):
        raise FileNotFoundError(f'{BAL_START_SCRIPT_PATH} not found')
    if not os.path.exists(CLOUD_FORMATION_COMMON_PATH):
        raise FileNotFoundError(f'{CLOUD_FORMATION_COMMON_PATH} not found')

def exec_command(cwd: str, command: List[str]):
    with open(os.devnull, 'wb') as devnull:
        process = subprocess.Popen(
            command, 
            cwd=cwd, 
            stdout=devnull, 
            stderr=devnull, 
            stdin=devnull, 
            start_new_session=True,  # Detach from parent
            preexec_fn=os.setpgrp  # Detach process group on Unix-like systems
        )
        print(f'Process started with PID: {process.pid}')

def get_config(config_path:str)->TestConfig:
    with open(config_path) as f:
        config = json.load(f)
    return config

def get_machine_configs()->Dict[str, MachineConfig]:
    with open(f'{SCRIPT_DIR}/machine_config.json') as f:
        config = json.load(f)
    return config

def validate_configs(test_config: TestConfig, machine_configs:Dict[str, MachineConfig]):
    for instance in test_config['test_grid']['instance_types']:
        if instance not in machine_configs:
            raise ValueError(f'Machine {instance} not found in machine_configs')
        instance = machine_configs[instance]
        if instance['arch'] == 'arm64':
            raise ValueError(f'arm64 is not supported yet')

if __name__ == '__main__':
    # validate_paths()
    testConfig = get_config(f'{SCRIPT_DIR}/config.json')
    machine_configs = get_machine_configs()
    validate_configs(testConfig, machine_configs)
    cwd = os.getcwd()
    exec_command(os.getcwd(), ['python3', 'runner.py', 'config.json', '123', 'token'])
