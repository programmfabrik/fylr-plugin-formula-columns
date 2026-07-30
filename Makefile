# fylr plugins are built by fylr-build-plugin, the build driver that knows how
# a fylr plugin is put together (compile, assemble build/, zip, seal, loca).
# This Makefile is a thin shim for muscle memory — all logic lives in the
# tool. @latest always resolves the tool's newest release, so plugins pick up
# fixes without being touched; an incompatible tool change would come as a new
# major version (import path .../v2), which is the only event that changes
# this line.
#
# Tools needed (each only for the features this plugin uses):
#   go       runs fylr-build-plugin — https://go.dev/dl/
#   coffee   CoffeeScript 1.x:  npm install -g coffeescript@1.12.7
#   sass     npm install -g sass
FYLR_BUILD_PLUGIN ?= go run github.com/programmfabrik/fylr-build-plugin@latest

# The tool itself reads NO environment variables — everything is passed as
# flags. The release workflow's RELEASE_TAG / ZIP_NAME env is translated into
# flags right here.
RELEASE_FLAGS = $(if $(RELEASE_TAG),-release "$(RELEASE_TAG)")
ZIP_FLAGS = $(RELEASE_FLAGS) $(if $(ZIP_NAME),-out "$(ZIP_NAME)")

# The manifest master is manifest.master.yml, like in the other fylr plugins.
# A permanent manifest.yml in the repo root makes a fylr server whose
# plugin.paths crawls this directory find the plugin twice — here and in
# build/ — and refuse to start with "Already loaded before with the same name".
# fylr-build-plugin insists on reading manifest.yml from the root, so it is
# generated for the run and removed again, also when the tool fails.
MANIFEST_MASTER = manifest.master.yml
run = cp $(MANIFEST_MASTER) manifest.yml && $(FYLR_BUILD_PLUGIN) $(1); rc=$$?; rm -f manifest.yml; exit $$rc

help:
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

all: build ## build all

build: ## build the plugin into build/<name>/ — loadable by fylr via plugin.paths
	$(call run,build $(RELEASE_FLAGS))

zip: ## build the release zip
	$(call run,zip $(ZIP_FLAGS))

loca: ## pull the loca CSV from its Google Sheets master (build.yml)
	$(call run,loca)

check: ## validate the build tree against the manifest
	$(call run,check)

clean: ## clean build files
	$(FYLR_BUILD_PLUGIN) clean
	rm -f manifest.yml

.PHONY: help all build zip loca check clean
