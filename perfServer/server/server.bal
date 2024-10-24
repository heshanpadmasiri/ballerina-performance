import ballerina/file;
import ballerina/http;
import ballerina/io;
import ballerina/lang.runtime as runtime;
import ballerina/os;

const epKeyPath = "ballerinaKeystore.p12";
configurable string password = ?;
configurable string JAVA_HOME = "/home/ubuntu/jdk/jdk-17.0.13+11";
configurable int port = 443;
configurable string resourcePrefix = "/home/ubuntu/perf";

configurable string ballerinaPerformanceRepo = "heshanpadmasiri/ballerina-performance.git";
configurable string ballerinaPerformanceBranch = "feat/automation";
configurable string performanceCommonRepo = "heshanpadmasiri/performance-common.git";
configurable string performanceCommonBranch = "ballerina-patch";

configurable string keyStorePath = "./ballerinaKeystore.p12";
configurable string trustStorePath = "./ballerinaTruststore.p12";

const string PERF_TAR_FILE = "ballerina-performance-distribution-1.1.1-SNAPSHOT.tar.gz";
const string NETTY_JAR_FILE = "netty-http-echo-service-0.4.6-SNAPSHOT.jar";
const string PAYLOD_GENERATOR_JAR_FILE = "payload-generator-0.4.6-SNAPSHOT.jar";

listener http:Listener ep = new (port,
    secureSocket = {
        key: {
            path: epKeyPath,
            password: password
        }
    }
);

service / on ep {
    final string basePath;
    final RunContext runContext = new RunContext();

    function init() {
        self.basePath = "./runArtifacts";
        checkpanic createDirIfNotExists(self.basePath);
    }

    resource function post triggerPerfTest(TestConfig testConfig) returns PerfTestTiggerResult {
        io:println("Triggering performance test");
        error? result = self.runTest(testConfig);
        if result is error {
            string errorMessage = "Failed to trigger the performance test due to " + result.message();
            error? e = writeToPr(errorMessage, testConfig.token);
            io:println(e);
            return {message: result.message()};
        }
        return "success";
    }

    isolated function runTest(TestConfig testConfig) returns error? {
        self.runContext.initTest({runConfig: {JAVA_HOME}, basePath: self.basePath}, testConfig);
    }
}

isolated function createDirIfNotExists(string path) returns error? {
    if !check file:test(path, file:EXISTS) {
        return file:createDir(path);
    }
}

type RunConfig record {|
    string JAVA_HOME;
|};

type BuildConfig readonly & record {|
    RunConfig runConfig;
    string basePath;
|};

isolated class RunContext {
    private final string buildBasePath = "./buildArtifacts";

    function init() {
        checkpanic createDirIfNotExists(self.buildBasePath);
    }

    isolated function initTest(BuildConfig buildConfig, TestConfig testConfig) {
        _ = start self.startBuild(buildConfig, testConfig);
    }

    isolated function startBuild(BuildConfig buildConfig, TestConfig testConfig) returns error? {
        string|error distPath = buildDist({JAVA_HOME}, buildConfig.basePath);
        if distPath is error {
            string message = "Failed to build the distribution due to " + distPath.message();
            check writeToPr(message, testConfig.token);
            return distPath;
        }
        return self.addToRunQueue(distPath, testConfig);
    }

    isolated function addToRunQueue(string distPath, TestConfig config) returns error? {
        error? res = runTest(self.buildBasePath, distPath, config);
        if res is error {
            string message = "Failed to run the performance test due to " + res.message();
            check writeToPr(message, config.token);
            return res;
        }
    }
}

isolated function runTest(string basePath, string distPath, TestConfig config) returns error? {
    io:println("Running performance test");
    check writeToPr("Performance test triggered", config.token);
    io:println(string `trying to download the ballerina installer from ${config.balInstallerUrl}`);
    check tryRun(exec("curl", ["-L", "-o", string `${distPath}/ballerina-installer.deb`, config.balInstallerUrl]));
    var [command, args] = getRunCommand(config);
    io:println("Running performance tests");
    string workingDir = distPath;
    check tryRun(exec(command, args, cwd = workingDir, env = {"AWS_PAGER": ""}));
}

isolated function writeResultsBackToGithub(string workingDir, TestConfig config) returns error? {
    string resultString = check getResultString(workingDir);
    return writeToPr(resultString, config.token);
}

isolated function writeToPr(string message, string token) returns error? {
    io:println(string `writing to PR ${message}`);
    string REPO = "ballerina-performance";
    string OWNER = "heshanpadmasiri";
    string PR_NUMBER = "2";
    // FIXME:
    http:Client githubClient = check new ("https://api.github.com", auth = {token});
    json|error ignored = githubClient->/repos/[OWNER]/[REPO]/issues/[PR_NUMBER]/comments.post({body: message});
    if ignored is error {
        io:println("Failed to write the message back to the PR due to " + ignored.message());
    }
}

isolated function getResultString(string workingDir) returns string|error {
    return "done";
}

isolated function userCount(TestConfig config) returns string {
    return " ".join(from int concurrentUser in config.concurrentUsers
        select string `-u ${concurrentUser}`);
}

isolated function messageSize(TestConfig config) returns string {
    return " ".join(from int messageSize in config.messageSizes
        select string `-b ${messageSize}`);
}

isolated function getIncludeTests(TestConfig config) returns string? {
    string[]? includeTests = config.includeTests;
    if includeTests is () {
        return ();
    }
    return " ".join(from string test in includeTests
        select string `-i ${test}`);
}

isolated function getExcludeTests(TestConfig config) returns string? {
    string[]? excludeTests = config.excludeTests;
    if excludeTests is () {
        return ();
    }
    return " ".join(from string test in excludeTests
        select string `-e ${test}`);
}

isolated function getRunCommand(TestConfig config) returns [string, string[]] {
    // FIXME: deb
    string command = "./cloudformation/run-performance-tests.sh";
    string[] args = [
        "-u heshanp@wso2.com",
        "-f ./ballerina-performance-distribution-1.1.1-SNAPSHOT.tar.gz ",
        string `-k ${resourcePrefix}/bhashinee-ballerina.pem`,
        "-n bhashinee-ballerina",
        string `-j ${resourcePrefix}/apache-jmeter-5.1.1.tgz`,
        string `-o ${resourcePrefix}/jdk-8u345-linux-x64.tar.gz`,
        string `-g ${resourcePrefix}/gcviewer-1.36.jar`,
        "-s 'wso2-ballerina-test1-'",
        "-b ballerina-sl-9",
        "-r 'us-east-1'",
        "-J c5.xlarge",
        "-S c5.xlarge",
        "-N c5.xlarge",
        string `-B ${config.vm}`,
        string `-i ./ballerina-installer.deb`,
        "--",
        "-d 360",
        "-w 180"
    ];

    string? includeTests = getIncludeTests(config);
    if includeTests is string {
        args.push(includeTests);
    }

    string? excludeTests = getExcludeTests(config);
    if excludeTests is string {
        args.push(excludeTests);
    }

    args.push(
        userCount(config),
        messageSize(config),
        "-s 0",
        "-j 2G",
        "-k 2G",
        "-l 2G",
        string `-m ${config.heapSize}G`
    );
    return [command, args];
}

isolated function buildDist(RunConfig runConfig, string basePath) returns string|error {
    string artificatDir = check file:createTempDir(dir = basePath);
    string ballerinaPerfDir = check file:createTempDir(suffix = "ballerina-performance", dir = artificatDir);
    io:println("Cloning ballerina performance repository");
    check cloneRepository(string `https://github.com/${ballerinaPerformanceRepo}`, ballerinaPerformanceBranch, ballerinaPerfDir);
    io:println("Cloning performance common repository");
    string perfCommonDir = check file:createTempDir(suffix = "performance-common", dir = artificatDir);
    check cloneRepository(string `https://github.com/${performanceCommonRepo}`, performanceCommonBranch, perfCommonDir);
    io:println("Building distribution");
    return buildDistribution(runConfig, basePath, ballerinaPerfDir, perfCommonDir);
}

isolated function buildDistribution(RunConfig config, string basePath, string ballerinaPerfDir, string perfCommonDir) returns string|error {
    io:println("Building performance common");
    check buildPerformanceCommon(config, perfCommonDir);
    string nettyPath = check getNettyPath(perfCommonDir);
    string payloadGenerator = check getPayloadGeneratorPath(perfCommonDir);
    io:println("Building ballerina performance");
    check buildBallerinaPerformance(config, ballerinaPerfDir);
    string perfDistPath = check getPerfDistPath(ballerinaPerfDir);
    io:println("Patching performance distribution");
    // string newPerfDistpath = check patchPerfDist(basePath, perfDistPath, nettyPath, payloadGenerator, [
    //             {sourcePath: string `${perfCommonDir}/distribution/scripts/cloudformation`, targetPath: "cloudformation"},
    //             {sourcePath: string `${perfCommonDir}/distribution/scripts/jmeter`, targetPath: "jmeter"}
    //         ]);
    string newPerfDistpath = check patchPerfDist(basePath, perfDistPath, nettyPath, payloadGenerator);
    // TODO: delete old perf dist
    return newPerfDistpath;
}

type ScriptReplacement record {
    string sourcePath;
    string targetPath;
};

isolated function patchPerfDist(string basePath, string perfDistPath, string nettyPath, string? payloadGeneratorPath, ScriptReplacement[] scriptReplacements = []) returns string|error {
    string extractDir = "/home/ubuntu/ballerina-performance-distribution-1.1.1-SNAPSHOT";
    if check file:test(extractDir, file:EXISTS) {
        check file:remove(extractDir, file:RECURSIVE);
    }
    check file:createDir(extractDir);

    check tryRun(exec("tar", ["-xvf", perfDistPath, "-C", extractDir]));
    check file:copy(nettyPath, string `${extractDir}/netty-service/${NETTY_JAR_FILE}`, file:REPLACE_EXISTING);
    if payloadGeneratorPath != () {
        check file:copy(payloadGeneratorPath, string `${extractDir}/dist/payloads/${PAYLOD_GENERATOR_JAR_FILE}`, file:REPLACE_EXISTING);
    }
    foreach var {sourcePath, targetPath} in scriptReplacements {
        if !check file:test(sourcePath, file:EXISTS) {
            return error(string `Source path ${sourcePath} doesn't exists`);
        }
        if !check file:test(sourcePath, file:IS_DIR) {
            check file:copy(sourcePath, string `${extractDir}/${targetPath}`, file:REPLACE_EXISTING);
        }
        string actualTargetPath = string `${extractDir}/${targetPath}`;
        if !check file:test(actualTargetPath, file:IS_DIR) {
            return error(string `Target path ${actualTargetPath} doesn't exists`);
        }
        check file:copy(sourcePath, actualTargetPath, file:REPLACE_EXISTING);
    }
    check file:copy(keyStorePath, string `${extractDir}/ballerinaKeystore.p12`, file:REPLACE_EXISTING);
    check file:copy(trustStorePath, string `${extractDir}/ballerinaTruststore.p12`, file:REPLACE_EXISTING);
    check tryRun(exec("tar", ["-cvf", string `${extractDir}/${PERF_TAR_FILE}`, "-C", extractDir, "."]));
    return extractDir;
}

isolated function tryRun(os:Process|error proc) returns error? {
    if proc is error {
        return proc;
    }
    int exitCode = check proc.waitForExit();
    if (exitCode != 0) {
        return error("Failed to run the process");
    }
}

isolated function getPerfDistPath(string ballerinaPerfDir) returns string|error {
    string perfDistPath = string `${ballerinaPerfDir}/distribution/target/${PERF_TAR_FILE}`;
    if !check file:test(perfDistPath, file:EXISTS) {
        return error(string ` Performance distribution path ${perfDistPath} doesn 't exists `);
    }
    return perfDistPath;
}

isolated function getNettyPath(string perfCommonDir) returns string|error {
    string nettyPath = string `${perfCommonDir}/components/netty-http-echo-service/target/netty-http-echo-service-0.4.6-SNAPSHOT-jar-with-dependencies.jar`;
    if !check file:test(nettyPath, file:EXISTS) {
        return error(string `Netty path ${nettyPath} doesn 't exists`);
    }
    return nettyPath;
}

isolated function getPayloadGeneratorPath(string perfCommonDir) returns string|error {
    string payloadGeneratorPath = string `${perfCommonDir}/components/payload-generator/target/${PAYLOD_GENERATOR_JAR_FILE}`;
    if !check file:test(payloadGeneratorPath, file:EXISTS) {
        return error(string `payload generator path ${payloadGeneratorPath} doesn't exists`);
    }
    return payloadGeneratorPath;
}

isolated function buildPerformanceCommon(RunConfig config, string perfCommonDir) returns error? {
    os:Process _ = check exec("mvn", ["clean", "package", "install", "-DskipTests"], config, perfCommonDir);
    io:println("waiting");
    // FIXME: sleep for 5 minutes, becuase proc.WaitForExit() is not working properly when using -DskipTests
    runtime:sleep(5 * 60);
    // int exitCode = check proc.waitForExit();
    // if (exitCode != 0) {
    //     string message = check string:fromBytes(check proc.output(io:stderr));
    //     return error(string `Failed to build performance common due to ${message}`);
    // }
    io:println("done");
}

isolated function buildBallerinaPerformance(RunConfig config, string ballerinaPerfDir) returns error? {
    os:Process proc = check exec("mvn", ["clean", "package"], config, ballerinaPerfDir);
    int exitCode = check proc.waitForExit();
    if (exitCode != 0) {
        return error("Failed to build ballerina performance");
    }
}

isolated function exec(string command, string[] args, os:EnvProperties? env = (), string? cwd = ()) returns os:Process|error {
    if cwd == () {
        io:println(string `${command} ${" ".join(...args)}`);
        return os:exec({value: command, arguments: args});
    }
    if env == () {
        string commandLine = string `cd ${cwd} && ${command} ${" ".join(...args)}`;
        io:println(commandLine);
        return os:exec({
                           value: "sh",
                           arguments: ["-c", commandLine]
                       });
    }
    string commandLine = string `cd ${cwd} && ${command} ${" ".join(...args)}`;
    io:println(commandLine);
    return os:exec({
                       value: "sh",
                       arguments: ["-c", commandLine]
                   }, env);
}

isolated function cloneRepository(string url, string branch, string targetPath) returns error? {
    if !check file:test(targetPath, file:EXISTS) {
        return error(string `Target path ${targetPath}  doesn't exists`);
    }
    os:Process proc = check os:exec({value: "git", arguments: ["clone", url, targetPath, "-b", branch]});
    int exitCode = check proc.waitForExit();
    if (exitCode != 0) {
        return error("Failed to clone the repository");
    }
}

// TODO: move to common
public type PerfTestTiggerResult "success"|record {string message;};

type VM "t3a.small";

type TestConfig readonly & record {|
    VM vm;
    int heapSize;
    int[] concurrentUsers;
    int[] messageSizes;
    string balInstallerUrl;
    string token;
    string[] includeTests?;
    string[] excludeTests?;
|};

