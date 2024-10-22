import ballerina/http;
import ballerina/io;

const epKeyPath = "ballerinaKeystore.p12";
const password = "ballerina";

listener http:Listener ep = new (443,
    secureSocket = {
        key: {
            path: epKeyPath,
            password: password
        }
    }
);

// listener http:Listener ep = new (9090);

service / on ep {
    resource function get echo() returns string {
        io:println("Inbound request received");
        return "test";
    }
}
