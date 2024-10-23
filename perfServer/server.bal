import ballerina/file;
import ballerina/http;
import ballerina/io;
import ballerina/os;

const epKeyPath = "ballerinaKeystore.p12";
configurable string password = ?;

listener http:Listener ep = new (443,
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
            return {message: result.message()};
        }
        return "success";
    }

    isolated function runTest() returns error? {
        RunConfig config = {};
        string distPath = check buildDist(self.basePath);
        return self.runContext.addToRunQueue(distPath, config);
    }
}

type RunConfig record {|
|};

isolated class RunContext {
    isolated function addToRunQueue(string distPath, RunConfig config) returns error? {
        io:println(distPath);
    }
}

isolated function buildDist(string basePath) returns string|error {
    string artificatDir = check file:createTempDir(dir = basePath);
    string ballerinaPerfDir = check file:createTempDir(dir = artificatDir);
    check cloneRepository("https://github.com/heshanpadmasiri/ballerina-performance.git", "feat/automation", ballerinaPerfDir);
    string perfCommonDir = check file:createTempDir(dir = artificatDir);
    check cloneRepository("https://github.com/heshanpadmasiri/performance-common.git", "ballerina-patch", perfCommonDir);
    return buildDistribution(ballerinaPerfDir, perfCommonDir);
}

isolated function buildDistribution(string ballerinaPerfDir, string perfCommonDir) returns string|error {
    check buildPerformanceCommon(perfCommonDir);
    string nettyPath = check getNettyPath(perfCommonDir);
    string payloadGenerator = check getPayloadGeneratorPath(perfCommonDir);
    check buildBallerinaPerformance(ballerinaPerfDir);
    string perfDistPath = check getPerfDistPath(ballerinaPerfDir);
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
    string perfDistPath = string ` ${ballerinaPerfDir} / distribution / target / ballerina - performance - distribution - 1.1 .1 - SNAPSHOT.tar.gz `;
    if !check file:test(perfDistPath, file:EXISTS) {
        return error(string ` Performance distribution path ${perfDistPath} doesn 't exists `);
    }
    return perfDistPath;
}

isolated function getNettyPath(string perfCommonDir) returns string|error {
    string nettyPath = string ` ${perfCommonDir} / components / netty - http - echo - service/ target / netty - http - echo - service-0.4 .6 - SNAPSHOT - jar - with - dependencies.jar `;
    if !check file:test(nettyPath, file:EXISTS) {
        return error(string ` Netty path ${nettyPath} doesn 't exists `);
    }
    return nettyPath;
}

isolated function getPayloadGeneratorPath(string perfCommonDir) returns string|error {
    string payloadGeneratorPath = string ` ${perfCommonDir} / components / payload - generator / target / payload - generator - 0.4 .6 - SNAPSHOT.jar `;
    if !check file:test(payloadGeneratorPath, file:EXISTS) {
        return error(string ` payload generator path ${payloadGeneratorPath} doesn 't exists `);
    }
    return payloadGeneratorPath;
}

isolated function buildPerformanceCommon(string perfCommonDir) returns error? {
    os:Process proc = check exec("mvn", ["package"], perfCommonDir);
    int exitCode = check proc.waitForExit();
    if (exitCode != 0) {
        return error("Failed to build performance common");
    }
}

isolated function buildBallerinaPerformance(string ballerinaPerfDir) returns error? {
    os:Process proc = check exec("mvn", ["package"], ballerinaPerfDir);
    int exitCode = check proc.waitForExit();
    if (exitCode != 0) {
        return error("Failed to build ballerina performance");
    }
}

isolated function exec(string command, string[] args, string? cwd = ()) returns os:Process|error {
    if cwd == () {
        return os:exec({value: command, arguments: args});
    }
    return os:exec({
                       value: "sh",
                       arguments: [
                           "-c",
                           string ` cd ${cwd} && ${command}${
        " ".join(...args)}
    `
                       ]
                   });
}

isolated function cloneRepository(string url, string branch, string targetPath) returns error? {
    if !check file:test(targetPath, file:EXISTS) {
        return error(string `    Target path ${targetPath}    doesn 't exists    `);
    }
    os:Process proc = check os:exec({value: "git", arguments: ["clone", url, targetPath, "-b", branch]});
    int exitCode = check proc.waitForExit();
    if (exitCode != 0) {
        return error("Failed to clone the repository");
    }
}

// TODO: move to common
public type PerfTestTiggerResult "success"|record {string message;};
