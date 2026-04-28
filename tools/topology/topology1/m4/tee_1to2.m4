divert(-1)

dnl V5.4.1 Phase 1a.3 — tee_1to2 component widget (1 mono src -> 2 mono sinks)
dnl Pattern emprunté à multiband_drc.m4 (UUID-based recognition by firmware).

DECLARE_SOF_RT_UUID("tee_1to2", tee_1to2_uuid, 0xe1ec7700, 0x5e44, 0x4abc,
		    0xb1, 0xf9, 0x3c, 0x14, 0xe2, 0xd2, 0xaf, 0xe1);

dnl N_TEE_1TO2(name)
define(`N_TEE_1TO2', `TEE_1TO2'PIPELINE_ID`.'$1)

dnl W_TEE_1TO2(name, format, periods_sink, periods_source, core)
define(`W_TEE_1TO2',
`SectionVendorTuples."'N_TEE_1TO2($1)`_tuples_uuid" {'
`	tokens "sof_comp_tokens"'
`	tuples."uuid" {'
`		SOF_TKN_COMP_UUID'		STR(tee_1to2_uuid)
`	}'
`}'
`SectionData."'N_TEE_1TO2($1)`_data_uuid" {'
`	tuples "'N_TEE_1TO2($1)`_tuples_uuid"'
`}'
`SectionVendorTuples."'N_TEE_1TO2($1)`_tuples_w" {'
`	tokens "sof_comp_tokens"'
`	tuples."word" {'
`		SOF_TKN_COMP_PERIOD_SINK_COUNT'		STR($3)
`		SOF_TKN_COMP_PERIOD_SOURCE_COUNT'	STR($4)
`		SOF_TKN_COMP_CORE_ID'			STR($5)
`	}'
`}'
`SectionData."'N_TEE_1TO2($1)`_data_w" {'
`	tuples "'N_TEE_1TO2($1)`_tuples_w"'
`}'
`SectionVendorTuples."'N_TEE_1TO2($1)`_tuples_str" {'
`	tokens "sof_comp_tokens"'
`	tuples."string" {'
`		SOF_TKN_COMP_FORMAT'	STR($2)
`	}'
`}'
`SectionData."'N_TEE_1TO2($1)`_data_str" {'
`	tuples "'N_TEE_1TO2($1)`_tuples_str"'
`}'
`SectionVendorTuples."'N_TEE_1TO2($1)`_tuples_str_type" {'
`	tokens "sof_process_tokens"'
`	tuples."string" {'
`		SOF_TKN_PROCESS_TYPE'	"TEE_1TO2"
`	}'
`}'
`SectionData."'N_TEE_1TO2($1)`_data_str_type" {'
`	tuples "'N_TEE_1TO2($1)`_tuples_str_type"'
`}'
`SectionWidget."'N_TEE_1TO2($1)`" {'
`	index "'PIPELINE_ID`"'
`	type "effect"'
`	no_pm "true"'
`	data ['
`		"'N_TEE_1TO2($1)`_data_uuid"'
`		"'N_TEE_1TO2($1)`_data_w"'
`		"'N_TEE_1TO2($1)`_data_str"'
`		"'N_TEE_1TO2($1)`_data_str_type"'
`	]'
`}')

divert(0)dnl
