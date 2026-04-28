divert(-1)

dnl V5.4.1 Phase 1a.3 — interleave_8 component widget (8 mono sources -> 1×8ch sink)
dnl Pattern emprunté à multiband_drc.m4 (UUID-based recognition).

DECLARE_SOF_RT_UUID("interleave_8", interleave_8_uuid, 0xc8a3b500, 0x5b95, 0x4cb1,
		    0xa9, 0x1c, 0x5a, 0x72, 0xfa, 0x4e, 0x9c, 0x5e);

dnl N_INTERLEAVE_8(name)
define(`N_INTERLEAVE_8', `INTERLEAVE_8'PIPELINE_ID`.'$1)

dnl W_INTERLEAVE_8(name, format, periods_sink, periods_source, core)
define(`W_INTERLEAVE_8',
`SectionVendorTuples."'N_INTERLEAVE_8($1)`_tuples_uuid" {'
`	tokens "sof_comp_tokens"'
`	tuples."uuid" {'
`		SOF_TKN_COMP_UUID'		STR(interleave_8_uuid)
`	}'
`}'
`SectionData."'N_INTERLEAVE_8($1)`_data_uuid" {'
`	tuples "'N_INTERLEAVE_8($1)`_tuples_uuid"'
`}'
`SectionVendorTuples."'N_INTERLEAVE_8($1)`_tuples_w" {'
`	tokens "sof_comp_tokens"'
`	tuples."word" {'
`		SOF_TKN_COMP_PERIOD_SINK_COUNT'		STR($3)
`		SOF_TKN_COMP_PERIOD_SOURCE_COUNT'	STR($4)
`		SOF_TKN_COMP_CORE_ID'			STR($5)
`	}'
`}'
`SectionData."'N_INTERLEAVE_8($1)`_data_w" {'
`	tuples "'N_INTERLEAVE_8($1)`_tuples_w"'
`}'
`SectionVendorTuples."'N_INTERLEAVE_8($1)`_tuples_str" {'
`	tokens "sof_comp_tokens"'
`	tuples."string" {'
`		SOF_TKN_COMP_FORMAT'	STR($2)
`	}'
`}'
`SectionData."'N_INTERLEAVE_8($1)`_data_str" {'
`	tuples "'N_INTERLEAVE_8($1)`_tuples_str"'
`}'
`SectionVendorTuples."'N_INTERLEAVE_8($1)`_tuples_str_type" {'
`	tokens "sof_process_tokens"'
`	tuples."string" {'
`		SOF_TKN_PROCESS_TYPE'	"INTERLEAVE_8"
`	}'
`}'
`SectionData."'N_INTERLEAVE_8($1)`_data_str_type" {'
`	tuples "'N_INTERLEAVE_8($1)`_tuples_str_type"'
`}'
`SectionWidget."'N_INTERLEAVE_8($1)`" {'
`	index "'PIPELINE_ID`"'
`	type "effect"'
`	no_pm "true"'
`	data ['
`		"'N_INTERLEAVE_8($1)`_data_uuid"'
`		"'N_INTERLEAVE_8($1)`_data_w"'
`		"'N_INTERLEAVE_8($1)`_data_str"'
`		"'N_INTERLEAVE_8($1)`_data_str_type"'
`	]'
`}')

divert(0)dnl
