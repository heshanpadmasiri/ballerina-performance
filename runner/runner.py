#!/usr/bin/env python
import argparse
import json
import os
import requests
import sys
import time
import zipfile
from typing import Generator, Optional, Tuple, TypedDict, List, Dict

DEBUG = False
DIST_PATH = os.path.abspath('..')
BAL_START_SCRIPT_PATH = f'{DIST_PATH}/ballerina/ballerina-start.sh'
SCRIPT_PATH = os.path.abspath(__file__)
SCRIPT_DIR = os.path.dirname(SCRIPT_PATH)
DIST_NAME = 'ballerina-performance-distribution-1.1.1-SNAPSHOT'
DIST_ZIP_PATH = os.path.abspath(f'{DIST_PATH}/../{DIST_NAME}.tar.gz')
CLOUD_FORMATION_COMMON_PATH = f'{DIST_PATH}/cloudformation/cloudformation-common.sh'

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

class MachineTestConfig(TypedDict):
    machine_name: str
    heap_sizes: List[int]
    active_process_counts: List[int]
    message_sizes: List[int]
    n_users: List[int]
    arch: str

class MachineConfig(TypedDict):
    memory: int
    cpu: int
    arch: str

class ExecConfig(TypedDict):
    bal_installer_path: str
    test_selection: str
    user_count: str
    message_size: str
    heap_size: str
    machine_name: str

def get_machine_data(machine_configs: Dict[str, MachineConfig], machine_name: str) -> MachineConfig:
    machine_data = machine_configs[machine_name]
    return machine_data

def heap_sizes(config: TestConfig)->List[str]:
    return config['test_grid']['heap_sizes']

def heap_size_as_gb(heap_size: str)->int:
    if heap_size[-1] != 'G':
        raise ValueError('Heap size must be in GB')
    return int(heap_size[:-1])

def get_heap_sizes_compatible_with_machine(config: TestConfig, machine_config: Dict[str, MachineConfig], machine_name: str) -> List[str]:
    machine_data = get_machine_data(machine_config, machine_name)
    config_heap_sizes = heap_sizes(config)
    return [heap_size for heap_size in config_heap_sizes if heap_size_as_gb(heap_size) < machine_data['memory']]

def get_active_process_counts_compatible_with_machine(config: TestConfig, machine_config: Dict[str, MachineConfig], machine_name: str) -> List[int]:
    machine_data = get_machine_data(machine_config, machine_name)
    return [process_count for process_count in config['test_grid']['active_process_counts'] if process_count <= machine_data['cpu']]

def get_test_config_for_machine(config: TestConfig, machine_config: Dict[str, MachineConfig], machine_name: str) -> MachineTestConfig:
    heap_sizes = get_heap_sizes_compatible_with_machine(config, machine_config, machine_name)
    active_process_counts = get_active_process_counts_compatible_with_machine(config, machine_config, machine_name)
    arch = machine_config[machine_name]['arch']
    return {
        'machine_name': machine_name,
        'heap_sizes': [heap_size_as_gb(each) for each in heap_sizes],
        'active_process_counts': active_process_counts,
        'message_sizes': config['test_grid']['message_sizes'],
        'n_users': config['test_grid']['n_users'],
        'arch': arch,
    }


def update_aarch_in_cloud_formation(arch:str):
    if arch != 'x86_64':
        raise ValueError(f'arch {arch} not supported')
    return
    # with open(CLOUD_FORMATION_COMMON_PATH, 'r') as f:
    #     lines = f.readlines()
    # target = arch_replace_map[arch]
    # lines = [line.replace(target, arch) for line in lines]
    # with open(CLOUD_FORMATION_COMMON_PATH, 'w') as f:
    #     f.writelines(lines)

def update_ballerina_start_script(n:int):
    # NOTE: not sure this is actually needed I think only updating tar gz file is enough
    update_ballerina_start_script_active_process_count(BAL_START_SCRIPT_PATH, n)
    temp_dir = f'{SCRIPT_DIR}/temp'
    if os.path.exists(temp_dir):
        os.system(f'rm -rf {temp_dir}')
    os.mkdir(f'{SCRIPT_DIR}/temp')
    os.system(f'tar -xzf {DIST_ZIP_PATH} -C {temp_dir}')
    if DEBUG:
        print (f'cp {BAL_START_SCRIPT_PATH} {temp_dir}/{DIST_NAME}/ballerina/ballerina-start.sh')
    os.system(f'cp {BAL_START_SCRIPT_PATH} {temp_dir}/{DIST_NAME}/ballerina/ballerina-start.sh')
    if DEBUG:
        print (f'tar -czf {DIST_ZIP_PATH} -C {temp_dir} .')
    os.system(f'tar -czf {DIST_ZIP_PATH} -C {temp_dir} .')

def update_ballerina_start_script_active_process_count(path:str, n:int):
    with open(path, 'r') as f:
        lines = f.readlines()
    for i, line in enumerate(lines):
        if line.startswith('nActiveProcess='):
            if n == -1:
                lines[i] = f'nActiveProcess=\n'
            else:
                lines[i] = f'nActiveProcess="-XX:ActiveProcessorCount={n}\n"'
            break;
    with open(path, 'w') as f:
        f.writelines(lines)

def user_count_string(test_config: TestConfig)-> str:
    parts = []
    for n_users in test_config['test_grid']['n_users']:
        parts.append(f'-u {n_users}')
    return ' '.join(parts) + ' '

def message_size_string(test_config: TestConfig) -> str:
    parts = []
    for message_size in test_config['test_grid']['message_sizes']:
        parts.append(f'-b {message_size}')
    return ' '.join(parts) + ' '

def test_selection_string(test_config):
    parts = []
    test_config = test_config['test_configs']
    for test in test_config['include_tests']:
        parts.append(f'-i {test}')
    for test in test_config['exclude_tests']:
        parts.append(f'-e {test}')
    if len(parts) == 0:
        return ''
    return ' '.join(parts) + ' '

def create_run_command(exec_config: ExecConfig) -> str:
    perf_prefix = os.getenv('PERF_PREFIX')
    command = ["./cloudformation/run-performance-tests.sh"]
    command.append("-u heshanp@wso2.com")
    command.append(f"-f {DIST_ZIP_PATH}")
    command.append(f"-k {perf_prefix}/bhashinee-ballerina.pem")
    command.append("-n bhashinee-ballerina")
    command.append(f"-j {perf_prefix}/apache-jmeter-5.1.1.tgz")
    command.append(f"-o {perf_prefix}/jdk-8u345-linux-x64.tar.gz")
    command.append(f"-g {perf_prefix}/gcviewer-1.36.jar")
    command.append("-s 'wso2-ballerina-test1-'")
    command.append("-b ballerina-sl-9")
    command.append("-r 'us-east-1'")
    command.append("-J c5.xlarge")
    command.append("-S c5.xlarge")
    command.append("-N c5.xlarge")
    command.append("-B " + exec_config['machine_name'])
    command.append("-i " + exec_config['bal_installer_path'])
    command.append("--")
    command.append(f"-d 360 -w 180 {exec_config['user_count']} {exec_config['message_size']}  -s 0 -j 2G -k 2G -m {exec_config['heap_size']} -l 2G")
    return ' '.join(command)

def exec_command(cwd: str, command: str):
    os.system(f'cd {cwd} && {command} > log.log')

def get_config(config_path:str)->TestConfig:
    with open(config_path) as f:
        config = json.load(f)
    return config

def get_machine_configs()->Dict[str, MachineConfig]:
    with open(f'{SCRIPT_DIR}/machine_config.json') as f:
        config = json.load(f)
    return config

def get_configs(test_config):
    for heap_size in test_config['heap_sizes']:
        yield test_config, heap_size

def get_exec_config(test_config: TestConfig, machine_test_config: MachineTestConfig) -> Generator[ExecConfig, None, None]:
    bal_installer_path = test_config['test_configs']['bal_installer_path']
    test_selection = "-i h1_transformation"
    user_count = user_count_string(test_config)
    message_size = message_size_string(test_config)
    machine_name = machine_test_config['machine_name']
    for heap_size in machine_test_config['heap_sizes']:
        yield {
            'bal_installer_path': bal_installer_path,
            'test_selection': test_selection,
            'user_count': user_count,
            'message_size': message_size,
            'heap_size': f'{heap_size}G',
            'machine_name': machine_name
        }


failed_indices = 0

class RootContext:
    def __init__(self):
        self.result_dirs = []

    def append_test_dir(self, path:str) -> None:
        self.result_dirs.append(path)

    def get_summary_paths(self) -> List[str]:
        return [f'{result_dir}/summary.md' for result_dir in self.result_dirs]

    def __get_result_dir_triple__(self) -> Generator[Tuple[str, Optional[str], Optional[str]], None, None]:
        for result_dir in self.result_dirs:
            test_config_path = f'{result_dir}/test_config.json'
            summary_path = self.__get_optional_path__(f'{result_dir}/summary.csv')
            log_path = self.__get_optional_path__(f'{result_dir}/results-1/run.log')
            yield test_config_path, summary_path, log_path

    def __get_optional_path__(self, path:str) -> Optional[str]:
        if os.path.exists(path):
            return path
        return None

    def __get_ouput_zip_path__(self) -> str:
        path = f'{DIST_PATH}/results.zip'
        if os.path.exists(path):
            os.remove(path)
        return path

    def generate_result_zip(self) -> None:
        with zipfile.ZipFile(self.__get_ouput_zip_path__(), 'w') as zipf:
            for i, (test_config_path, summary_path, log_path) in enumerate(self.__get_result_dir_triple__()):
                dir_name = f'result-{i}'
                zipf.write(test_config_path, f'{dir_name}/test_config.json')
                if summary_path:
                    zipf.write(summary_path, f'{dir_name}/summary.csv')
                if log_path:
                    zipf.write(log_path, f'{dir_name}/run.log')


class Context:
    def __init__(self, rootContext: RootContext, dist_path: str):
        self.dist_path = dist_path
        self.root_context = rootContext
        self.directories_in_dist = os.listdir(dist_path)

    def report_path(self)->str:
        new_directories = list(filter(lambda x: x not in self.directories_in_dist, os.listdir(self.dist_path)))
        if (len(new_directories) == 1):
            result_dir = f'{self.dist_path}/{new_directories[0]}'
            self.root_context.append_test_dir(result_dir)
            return f'{result_dir}/test_config.json'
        else:
            global failed_indices
            index = failed_indices
            failed_indices += 1
            return f'{self.dist_path}/test_config_{index}.json'

def record_test_config(cx: Context, config: ExecConfig):
    with open(cx.report_path(), 'w') as f:
        json.dump(config, f)


def validate_configs(test_config: TestConfig, machine_configs:Dict[str, MachineConfig]):
    for instance in test_config['test_grid']['instance_types']:
        if instance not in machine_configs:
            raise ValueError(f'Machine {instance} not found in machine_configs')
        instance = machine_configs[instance]
        if instance['arch'] == 'arm64':
            raise ValueError(f'arm64 is not supported yet')

def get_arg_parser()->argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description='Run performance tests')
    parser.add_argument('config', type=str, help='path to the test config file', default=f'{SCRIPT_DIR}/config.json')
    parser.add_argument('repo', type=str, help='repository name')
    parser.add_argument('pr', type=int, help='PR number')
    parser.add_argument('token', type=str, help='github token')
    parser.add_argument('--debug', action='store_true', help='debug mode')
    return parser

def write_to_pr(repo: str, pr_number:int, github_token:str, message:str):
    api_url = f"https://api.github.com/repos/{repo}/issues/{pr_number}/comments"
    comment = {
        "body": message
    }
    headers = {
        "Authorization": f"token {github_token}",
        "Accept": "application/vnd.github.v3+json"
    }
    response = requests.post(api_url, json=comment, headers=headers)
    if response.status_code == 201:
        print(f"Successfully added comment to PR #{pr_number}.")
    else:
        print(f"Failed to add comment: {response.status_code}, {response.text}")

def write_summary_to_pr(repo: str, pr_number:int, github_token:str, summary_path:str):
    with open(summary_path) as f:
        summary = f.read() 
        write_to_pr(repo, pr_number, github_token, summary)

def main():
    parser = get_arg_parser()
    args = parser.parse_args()
    if args.debug:
        global DEBUG
        DEBUG = True
        print(args)
    testConfig = get_config(args.config)
    machine_configs = get_machine_configs()
    validate_configs(testConfig, machine_configs)
    root_context = RootContext()
    write_to_pr(args.repo, args.pr, args.token, "Performance tests started")
    try:
        for machine_name in testConfig['test_grid']['instance_types']:
            machine_test_config = get_test_config_for_machine(testConfig, machine_configs, machine_name);
            write_to_pr(args.repo, args.pr, args.token, f"Config: {machine_test_config}")
            for run_config in get_exec_config(testConfig, machine_test_config):
                cx = Context(root_context, DIST_PATH)
                command = create_run_command(run_config)
                if DEBUG:
                    write_to_pr(args.repo, args.pr, args.token, command)
                exec_command(DIST_PATH, command)
                if DEBUG:
                    write_to_pr(args.repo, args.pr, args.token, "done")
                record_test_config(cx, run_config)
                time.sleep(5 * 60)
        root_context.generate_result_zip()
    except Exception as e:
        if DEBUG:
            write_to_pr(args.repo, args.pr, args.token, f"Error: {e}")
        sys.exit(1)
    write_to_pr(args.repo, args.pr, args.token, "Performance tests done")
    for each in root_context.get_summary_paths():
        write_summary_to_pr(args.repo, args.pr, args.token, each)

if __name__ == '__main__':
    main()

