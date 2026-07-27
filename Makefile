OUTPUT=build
JOB=q-set26

# Output directories
O_PAPER=$(abspath $(OUTPUT)/paper)
O_ANALYSIS=$(OUTPUT)/analysis
O_EXTRACTED=$(O_ANALYSIS)/extracted
O_ANALYSED=$(O_ANALYSIS)/analysed
O_TEX=$(OUTPUT)/tex

PROJECTS=projects/
CONF=analysis/conf.yml

RES_EXTRACTED=$(O_EXTRACTED)/all_identities.csv
RES_ANALYSED=$(O_ANALYSED)/contributions.csv

PLOTS=$(O_TEX)/violin_h_selected.tex
PROJECT_TABLE=$(O_ANALYSED)/project_stats.csv
TABLE=$(O_TEX)/table.tex

COMPOSE=docker/docker-compose.yml
DC=docker compose
CLI=./analysis/src/cli.py
R=Rscript

PAPER=$(O_PAPER)/$(JOB).pdf

OUTDIRS=$(O_PAPER)

all: $(PAPER)

$(OUTDIRS):
	mkdir -p $@

$(PAPER): paper/main.tex | $(OUTDIRS)
	latexmk -lualatex -cd -output-directory=$(O_PAPER) -jobname=$(JOB) $<

$(RES_EXTRACTED): $(CLI)
	$(CLI) -v extract $(PROJECTS) $(dir $@) $(CONF)

$(RES_ANALYSED): $(RES_EXTRACTED) $(CLI)
	$(CLI) -v analyse $(dir $<) $(dir $@)

$(PROJECT_TABLE): analysis/project_stats.py $(RES_ANALYSED)
	python3 $< \
		--contributions $(RES_ANALYSED) \
		--commits $(O_ANALYSED)/commits_processed.csv \
		--project_dir $(PROJECTS) \
		--filter $(CONF) \
		--csv $@

$(PLOTS) $(TABLE) &: ./analysis/analysis.R $(RES_ANALYSED) $(PROJECT_TABLE)
	$(R) $< $(O_TEX) $(O_ANALYSED)

repro_docker: $(COMPOSE)
	$(DC) -f $^ build
	$(DC) -f $^ run --rm repro

repro: $(PLOTS) $(TABLE)
	@echo "Up to date!"

dev: $(COMPOSE)
	$(DC) -f $^ run --rm $@

clean:
	rm -rf $(OUTPUT)
