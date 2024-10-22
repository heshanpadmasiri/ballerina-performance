import ballerina/http;
import ballerina/io;

const epTrustStorePath = "ballerinaTruststore.p12";
const password = "ballerina";

// const addr = "localhost";

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

    // http:Client 'client = check new ("localhost:9090");
    string response = check 'client->get("/echo");
    io:println(response);
}
