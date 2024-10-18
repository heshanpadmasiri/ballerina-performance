PERFORMANCE_COMMON_PATH?=../performance-common
KEY_FILE_PREFIX?=/opt/homebrew/Cellar/ballerina/2201.9.2/libexec/distributions/ballerina-2201.10.0/bre/security
KEY_FILES=$(KEY_FILE_PREFIX)/*.p12
NETTY_JAR_WITH_DEP?=netty-http-echo-service-0.4.6-SNAPSHOT-jar-with-dependencies.jar
NETTY_JAR=netty-http-echo-service-0.4.6-SNAPSHOT.jar
NETTY_JAR_PATH=$(PERFORMANCE_COMMON_PATH)/components/netty-http-echo-service/target/$(NETTY_JAR_WITH_DEP)
DIST_VER?=1.1.1-SNAPSHOT
DIST_NAME=ballerina-performance-distribution-$(DIST_VER)
PERF_TAR=$(DIST_NAME).tar.gz
PERF_TAR_PATH=./distribution/target/$(PERF_TAR)
BUILD_DIR=./build
DEB_URL?=https://dist.ballerina.io/downloads/2201.10.1/ballerina-2201.10.1-swan-lake-linux-x64.deb
UNPACK_STAMP=.unpack.stamp
NETTY_REPLACE_STAMP=.netty.stamp
KEY_STAMP=.key.stamp
REPACK_STAMP=.repack.stamp
DEB_STAMP=.deb.stamp
DIST_STAMP=.dist.stamp

dist: $(DIST_STAMP)

$(DIST_STAMP): $(REPACK_STAMP) $(DEB_STAMP)
	tar -czf $(BUILD_DIR)/dist.tar.gz -C $(BUILD_DIR) $(PERF_TAR) ballerina-2201.10.1-swan-lake-linux-x64.deb
	touch $(DIST_STAMP)

$(NETTY_JAR_PATH):
	cd $(PERFORMANCE_COMMON_PATH) && mvn package

$(DEB_STAMP): $(REPACK_STAMP)
	cd $(BUILD_DIR) && wget $(DEB_URL)
	touch $(DEB_STAMP)

$(REPACK_STAMP): $(KEY_STAMP) $(NETTY_REPLACE_STAMP)
	cp ./runtest.sh $(BUILD_DIR)/dist/
	mkdir -p $(BUILD_DIR)/dist/$(DIST_NAME)
	mv $(BUILD_DIR)/dist/ $(BUILD_DIR)/$(DIST_NAME)
	tar -czf $(BUILD_DIR)/$(DIST_NAME).tar.gz -C $(BUILD_DIR) $(DIST_NAME)
	rm -rf $(BUILD_DIR)/$(DIST_NAME)
	touch $(REPACK_STAMP)

$(PERF_TAR_PATH):
	mvn clean package

$(KEY_STAMP): $(KEY_FILES) $(UNPACK_STAMP)
	cp $(KEY_FILES) $(BUILD_DIR)/dist
	touch $(KEY_STAMP)

$(NETTY_REPLACE_STAMP): $(NETTY_JAR_PATH) $(UNPACK_STAMP)
	rm -f $(BUILD_DIR)/dist/netty-service/$(NETTY_JAR)
	cp $(NETTY_JAR_PATH) $(BUILD_DIR)/dist/netty-service/$(NETTY_JAR)
	touch $(NETTY_REPLACE_STAMP)

$(UNPACK_STAMP): $(PERF_TAR_PATH) 
	mkdir -p $(BUILD_DIR)/dist
	tar -xzf $(PERF_TAR_PATH) -C $(BUILD_DIR)/dist
	touch $(UNPACK_STAMP)

clean:
	cd $(PERFORMANCE_COMMON_PATH) && mvn clean
	mvn clean
	rm -rf *.stamp
	rm -rf $(BUILD_DIR)

.PHONY: clean
