divert(-1)

dnl V5.4.1 Phase 1a.3 — mixer16 component widget (16 sources × 8 sinks matrix)
dnl Pattern emprunté à multiband_drc.m4 (UUID-based recognition).
dnl Bytes blob 512 B (128 cellules Q1.31) exposé via mixer16_control_<id>.

DECLARE_SOF_RT_UUID("mixer16", mixer16_uuid, 0xd2e64a00, 0xe3b6, 0x4dca,
		    0xbd, 0x83, 0x09, 0xe8, 0xaa, 0xe6, 0xe1, 0xf7);

dnl N_MIXER16(name)
define(`N_MIXER16', `MIXER16'PIPELINE_ID`.'$1)

dnl W_MIXER16(name, format, periods_sink, periods_source, core, kcontrol_list)
define(`W_MIXER16',
`SectionVendorTuples."'N_MIXER16($1)`_tuples_uuid" {'
`	tokens "sof_comp_tokens"'
`	tuples."uuid" {'
`		SOF_TKN_COMP_UUID'		STR(mixer16_uuid)
`	}'
`}'
`SectionData."'N_MIXER16($1)`_data_uuid" {'
`	tuples "'N_MIXER16($1)`_tuples_uuid"'
`}'
`SectionVendorTuples."'N_MIXER16($1)`_tuples_w" {'
`	tokens "sof_comp_tokens"'
`	tuples."word" {'
`		SOF_TKN_COMP_PERIOD_SINK_COUNT'		STR($3)
`		SOF_TKN_COMP_PERIOD_SOURCE_COUNT'	STR($4)
`		SOF_TKN_COMP_CORE_ID'			STR($5)
`	}'
`}'
`SectionData."'N_MIXER16($1)`_data_w" {'
`	tuples "'N_MIXER16($1)`_tuples_w"'
`}'
`SectionVendorTuples."'N_MIXER16($1)`_tuples_str" {'
`	tokens "sof_comp_tokens"'
`	tuples."string" {'
`		SOF_TKN_COMP_FORMAT'	STR($2)
`	}'
`}'
`SectionData."'N_MIXER16($1)`_data_str" {'
`	tuples "'N_MIXER16($1)`_tuples_str"'
`}'
`SectionVendorTuples."'N_MIXER16($1)`_tuples_str_type" {'
`	tokens "sof_process_tokens"'
`	tuples."string" {'
`		SOF_TKN_PROCESS_TYPE'	"MIXER16"
`	}'
`}'
`SectionData."'N_MIXER16($1)`_data_str_type" {'
`	tuples "'N_MIXER16($1)`_tuples_str_type"'
`}'
`SectionWidget."'N_MIXER16($1)`" {'
`	index "'PIPELINE_ID`"'
`	type "effect"'
`	no_pm "true"'
`	data ['
`		"'N_MIXER16($1)`_data_uuid"'
`		"'N_MIXER16($1)`_data_w"'
`		"'N_MIXER16($1)`_data_str"'
`		"'N_MIXER16($1)`_data_str_type"'
`	]'
`	bytes ['
		$6
`	]'
`}')

divert(0)dnl
