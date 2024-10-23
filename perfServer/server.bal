import ballerina/file;
import ballerina/http;
import ballerina/io;
import ballerina/os;

const epKeyPath = "ballerinaKeystore.p12";
configurable string password = ?;
configurable string JAVA_HOME = "/home/ubuntu/jdk/jdk-17.0.13+11";
configurable int PORT = 443;

listener http:Listener ep = new (PORT,
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
        checkpanic file:createDir(self.basePath);
    }

    resource function get triggerPerfTest() returns PerfTestTiggerResult {
        io:println("Triggering performance test");
        error? result = self.runTest();
        if result is error {
            io:println("Failed to trigger the performance test due to " + result.message());
            return {message: result.message()};
        }
        return "success";
    }

    isolated function runTest() returns error? {
        self.runContext.initTest({runConfig: {JAVA_HOME}, basePath: self.basePath});
    }
}

type RunConfig record {|
    string JAVA_HOME;
|};

type Build readonly & record {|
    RunConfig runConfig;
    string basePath;
|};

type TestConfig record {|
|};

isolated class RunContext {

    isolated function initTest(Build build) {
        future<error?> result = start self.startBuild(build);
    }

    isolated function startBuild(Build build) returns error? {
        string|error distPath = buildDist({JAVA_HOME}, build.basePath);
        if distPath is error {
            io:println("Failed to build the distribution due to " + distPath.message());
            return distPath;
        }
        return self.addToRunQueue(distPath, {});
    }

    isolated function addToRunQueue(string distPath, TestConfig config) returns error? {
        io:println(distPath);
    }
}

isolated function buildDist(RunConfig runConfig, string basePath) returns string|error {
    string artificatDir = check file:createTempDir(dir = basePath);
    string ballerinaPerfDir = check file:createTempDir(dir = artificatDir);
    io:println("Cloning ballerina performance repository");
    check cloneRepository("https://github.com/heshanpadmasiri/ballerina-performance.git", "feat/automation", ballerinaPerfDir);
    io:println("Cloning performance common repository");
    string perfCommonDir = check file:createTempDir(dir = artificatDir);
    check cloneRepository("https://github.com/heshanpadmasiri/performance-common.git", "ballerina-patch", perfCommonDir);
    io:println("Building distribution");
    return buildDistribution(runConfig, ballerinaPerfDir, perfCommonDir);
}

isolated function buildDistribution(RunConfig config, string ballerinaPerfDir, string perfCommonDir) returns string|error {
    io:println("Building performance common");
    check buildPerformanceCommon(config, perfCommonDir);
    string nettyPath = check getNettyPath(perfCommonDir);
    string payloadGenerator = check getPayloadGeneratorPath(perfCommonDir);
    io:println("Building ballerina performance");
    check buildBallerinaPerformance(config, ballerinaPerfDir);
    string perfDistPath = check getPerfDistPath(ballerinaPerfDir);
    io:println("Patching performance distribution");
    check patchPerfDist(perfDistPath, nettyPath, payloadGenerator);
    return perfDistPath;
}

type ScriptReplacement record {
    string sourcePath;
    string targetPath;
};

isolated function patchPerfDist(string perfDistPath, string nettyPath, string payloadGeneratorPath, ScriptReplacement[] scriptReplacements = []) returns error? {
    string tempDir = check file:createTempDir();
    string extractDir = string `${tempDir}/extracted`;
    check file:createDir(extractDir);
    check tryRun(exec("tar", ["-xvf", perfDistPath, "-C", extractDir]));
    check file:copy(nettyPath, string `${extractDir}/netty-service/netty-http-echo-service-0.4.6-SNAPSHOT.jar`, file:REPLACE_EXISTING);
    check file:copy(payloadGeneratorPath, string `${extractDir}/dist/payloads/payload-generator-0.4.6-SNAPSHOT.jar`, file:REPLACE_EXISTING);
    foreach var {sourcePath, targetPath} in scriptReplacements {
        if !check file:test(sourcePath, file:EXISTS) {
            return error(string `Source path ${sourcePath} doesn't exists`);
        }
        if !check file:test(sourcePath, file:IS_DIR) {
            check file:copy(sourcePath, string `${extractDir}/${targetPath}`, file:REPLACE_EXISTING);
        }
        check file:remove(sourcePath, file:RECURSIVE);
        check file:copy(sourcePath, string `${extractDir}/${targetPath}`);
    }
    check tryRun(exec("tar", ["-cvf", perfDistPath, "-C", extractDir, "."]));
    check file:remove(tempDir, file:RECURSIVE);
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
    string perfDistPath = string `${ballerinaPerfDir}/distribution/target/ballerina-performance-distribution-1.1.1-SNAPSHOT.tar.gz`;
    if !check file:test(perfDistPath, file:EXISTS) {
        return error(string ` Performance distribution path ${perfDistPath} doesn 't exists `);
    }
    return perfDistPath;
}

isolated function getNettyPath(string perfCommonDir) returns string|error {
    string nettyPath = string `${perfCommonDir}/components/netty-http-echo-service/target/netty-http-echo-service-0.4.6-SNAPSHOT-jar-with-dependencies.jar`;
    if !check file:test(nettyPath, file:EXISTS) {
        return error(string ` Netty path ${nettyPath} doesn 't exists `);
    }
    return nettyPath;
}

isolated function getPayloadGeneratorPath(string perfCommonDir) returns string|error {
    string payloadGeneratorPath = string `${perfCommonDir}/components/payload-generator/target/payload-generator-0.4.6-SNAPSHOT.jar`;
    if !check file:test(payloadGeneratorPath, file:EXISTS) {
        return error(string ` payload generator path ${payloadGeneratorPath} doesn 't exists `);
    }
    return payloadGeneratorPath;
}

isolated function buildPerformanceCommon(RunConfig config, string perfCommonDir) returns error? {
    os:Process proc = check exec("mvn", ["package"], config, perfCommonDir);
    int exitCode = check proc.waitForExit();
    if (exitCode != 0) {
        string message = check string:fromBytes(check proc.output(io:stderr));
        return error(string `Failed to build performance common due to ${message}`);
    }
}

isolated function buildBallerinaPerformance(RunConfig config, string ballerinaPerfDir) returns error? {
    os:Process proc = check exec("mvn", ["package"], config, ballerinaPerfDir);
    int exitCode = check proc.waitForExit();
    if (exitCode != 0) {
        return error("Failed to build ballerina performance");
    }
}

isolated function exec(string command, string[] args, RunConfig? config = (), string? cwd = ()) returns os:Process|error {
    if cwd == () {
        return os:exec({value: command, arguments: args});
    }
    if config == () {
        return os:exec({
                           value: "sh",
                           arguments: ["-c", string `cd ${cwd} && ${command} ${" ".join(...args)}`]
                       });
    }
    return os:exec({
                       value: "sh",
                       arguments: ["-c", string `cd ${cwd} && ${command} ${" ".join(...args)}`]
                   }, config);
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
