rm -f server.zip
bal build
zip server.zip ./target/bin/server.jar *.p12
