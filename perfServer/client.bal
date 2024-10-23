import ballerina/http;
import ballerina/io;

const epTrustStorePath = "ballerinaTruststore.p12";
configurable string password = ?;
configurable string host = "localhost";
configurable int port = 9090;

public function main() returns error? {
    http:Client 'client = check new (string `${host}:${port}`,
        secureSocket = {
            cert: {
                path: epTrustStorePath,
                password: password
            },
            verifyHostName: false
        }
    );

    TestConfig config = {
        vm: "t3a.small",
        heapSize: 1,
        concurrentUsers: [100],
        messageSizes: [100],
        balInstallerUrl: "https://dist.ballerina.io/downloads/2201.10.2/ballerina-2201.10.2-swan-lake-linux-x64.deb"
    };
    // FIXME: create issue for this, not working with PerfTestTiggerResult
    string|record {|string message;|} response = check 'client->/triggerPerfTest.post(config);
    io:println(response);
    if response !is string {
        return error(string `failed to trigger the performance test due to ${response.message}`);
    }
    io:println("Performance test triggered successfully");
}

public type PerfTestTiggerResult "success"|record {string message;};

type VM "t3a.small";

type TestConfig readonly & record {|
    VM vm;
    int heapSize;
    int[] concurrentUsers;
    int[] messageSizes;
    string balInstallerUrl;
    string[] includeTests?;
    string[] excludeTests?;
|};

