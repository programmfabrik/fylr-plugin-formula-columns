ZIP_NAME ?= "formula-columns.zip"

COFFEE_FILES_WEB = \
	webfrontend/CustomDatamodelSettings.coffee

JS_WEB = webfrontend/FormulaColumns.js

SCSS_FILES = webfrontend/FormulaColumns.scss

help:
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

all: build ## build all


css:
	sass $(SCSS_FILES) build/formula-columns/webfrontend/FormulaColumns.css

code: $(JS_WEB) $(JS_SERVER) ## build Coffeescript code

build: clean code css## copy files to build folder
	mkdir -p build/formula-columns
	cp -r l10n build/formula-columns
	cp -r manifest.master.yml build/formula-columns/manifest.yml
	mkdir -p build/formula-columns/webfrontend
	mkdir -p build/formula-columns/server
	cp -r $(JS_WEB) build/formula-columns/webfrontend
	cp -r server/FormulaColumnsServer.js build/formula-columns/server
	cp -r lib build/formula-columns/

clean: ## clean
	rm -rf build

zip: build ## build zip file
	cd build && zip ${ZIP_NAME} -r formula-columns/

${JS_WEB}: $(subst .coffee,.coffee.js,${COFFEE_FILES_WEB})
	mkdir -p $(dir $@)
	cat $^ > $@

%.coffee.js: %.coffee
	coffee -b -p --compile "$^" > "$@" || ( rm -f "$@" ; false )
