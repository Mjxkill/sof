divert(-1)

dnl V5.4.1 Phase 1a.3 — deinterleave_8 component widget (1 source 8ch -> 8 mono sinks)
dnl Pattern miroir d'interleave_8.m4 (UUID-based recognition).

DECLARE_SOF_RT_UUID("deinterleave_8", deinterleave_8_uuid, 0xf1a2b3c4, 0xd5e6, 0x4789,
		    0xab, 0xcd, 0xef, 0x01, 0x23, 0x45, 0x67, 0x89);

dnl N_DEINTERLEAVE_8(name)
define(`N_DEINTERLEAVE_8', `DEINTERLEAVE_8'PIPELINE_ID`.'$1)

dnl W_DEINTERLEAVE_8(name, format, periods_sink, periods_source, core)
define(`W_DEINTERLEAVE_8',
`SectionVendorTuples."'N_DEINTERLEAVE_8($1)`_tuples_uuid" {'
`	tokens "sof_comp_tokens"'
`	tuples."uuid" {'
`		SOF_TKN_COMP_UUID'		STR(deinterleave_8_uuid)
`	}'
`}'
`SectionData."'N_DEINTERLEAVE_8($1)`_data_uuid" {'
`	tuples "'N_DEINTERLEAVE_8($1)`_tuples_uuid"'
`}'
`SectionVendorTuples."'N_DEINTERLEAVE_8($1)`_tuples_w" {'
`	tokens "sof_comp_tokens"'
`	tuples."word" {'
`		SOF_TKN_COMP_PERIOD_SINK_COUNT'		STR($3)
`		SOF_TKN_COMP_PERIOD_SOURCE_COUNT'	STR($4)
`		SOF_TKN_COMP_CORE_ID'			STR($5)
`	}'
`}'
`SectionData."'N_DEINTERLEAVE_8($1)`_data_w" {'
`	tuples "'N_DEINTERLEAVE_8($1)`_tuples_w"'
`}'
`SectionVendorTuples."'N_DEINTERLEAVE_8($1)`_tuples_str" {'
`	tokens "sof_comp_tokens"'
`	tuples."string" {'
`		SOF_TKN_COMP_FORMAT'	STR($2)
`	}'
`}'
`SectionData."'N_DEINTERLEAVE_8($1)`_data_str" {'
`	tuples "'N_DEINTERLEAVE_8($1)`_tuples_str"'
`}'
`SectionVendorTuples."'N_DEINTERLEAVE_8($1)`_tuples_str_type" {'
`	tokens "sof_process_tokens"'
`	tuples."string" {'
`		SOF_TKN_PROCESS_TYPE'	"DEINTERLEAVE_8"
`	}'
`}'
`SectionData."'N_DEINTERLEAVE_8($1)`_data_str_type" {'
`	tuples "'N_DEINTERLEAVE_8($1)`_tuples_str_type"'
`}'
`SectionWidget."'N_DEINTERLEAVE_8($1)`" {'
`	index "'PIPELINE_ID`"'
`	type "effect"'
`	no_pm "true"'
`	data ['
`		"'N_DEINTERLEAVE_8($1)`_data_uuid"'
`		"'N_DEINTERLEAVE_8($1)`_data_w"'
`		"'N_DEINTERLEAVE_8($1)`_data_str"'
`		"'N_DEINTERLEAVE_8($1)`_data_str_type"'
`	]'
`}')

divert(0)dnl
