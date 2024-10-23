import ballerina/http;
import ballerina/io;

const epTrustStorePath = "ballerinaTruststore.p12";
configurable string password = ?;
configurable string URL = "54.147.32.108";
configurable int PORT = 443;

public function main() returns error? {
    http:Client 'client = check new (string `${URL}:${PORT}`,
        secureSocket = {
            cert: {
                path: epTrustStorePath,
                password: password
            },
            verifyHostName: false
        }
    );

    // FIXME: create issue for this, not working with PerfTestTiggerResult
    string|record {|string message;|} response = check 'client->/triggerPerfTest();
    io:println(response);
    if response !is string {
        return error(string `failed to trigger the performance test due to ${response.message}`);
    }
    io:println("Performance test triggered successfully");
}

public type PerfTestTiggerResult "success"|record {string message;};
