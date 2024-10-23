import ballerina/file;
import ballerina/http;
import ballerina/log;
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

    function init() {
        self.basePath = "./runArtifacts";
        checkpanic file:createDir(self.basePath);
    }

    resource function get triggerPerfTest() returns PerfTestTiggerResult {
        log:printDebug("Triggering performance test");
        error? result = runPerfTest(self.basePath);
        if result is error {
            return {message: result.message()};
        }
        return "success";
    }
}

isolated function runPerfTest(string basePath) returns error? {
    string artificatDir = check file:createTempDir(dir = basePath);
    return cloneRepository("https://github.com/heshanpadmasiri/ballerina-performance.git", "feat/automation", artificatDir);
}

isolated function cloneRepository(string url, string branch, string targetPath) returns error? {
    if !check file:test(targetPath, file:EXISTS) {
        return error(string `Target path ${targetPath} doesn't exists`);
    }
    os:Process proc = check os:exec({value: "git", arguments: ["clone", url, targetPath, "-b", branch]});
    int exitCode = check proc.waitForExit();
    if (exitCode != 0) {
        return error("Failed to clone the repository");
    }
}

// TODO: move to common
public type PerfTestTiggerResult "success"|record {string message;};
