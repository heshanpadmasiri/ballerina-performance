import ballerina/http;
import ballerina/io;

const epTrustStorePath = "ballerinaTruststore.p12";
configurable string password = ?;

public function main() returns error? {
    http:Client 'client = check new ("54.147.32.108:443",
        secureSocket = {
            cert: {
                path: epTrustStorePath,
                password: password
            },
            verifyHostName: false
        }
    );

    PerfTestTiggerResult response = check 'client->/triggerPerfTest();
    io:println(response);
    if response !is "success" {
        return error(string `failed to trigger the performance test due to {response.message}`);
    }
}

public type PerfTestTiggerResult "success"|record {string message;};
