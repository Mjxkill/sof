divert(-1)

dnl V5.4.1 Phase 1a.3 E6.b — matrix_2x8 component widget (2 src 8ch -> 1 sink 8ch)
dnl Native interleaved replacement for mixer16 + deinterleave_8 x 2 + interleave_8 chain.

DECLARE_SOF_RT_UUID("matrix_2x8", matrix_2x8_uuid, 0xa3c7e012, 0x4f29, 0x4d8b,
		    0x9e, 0x15, 0x7a, 0x6c, 0x8b, 0x3d, 0x2f, 0x01);

dnl N_MATRIX_2X8(name)
define(`N_MATRIX_2X8', `MATRIX_2X8'PIPELINE_ID`.'$1)

dnl W_MATRIX_2X8(name, format, periods_sink, periods_source, core, kcontrol_list)
define(`W_MATRIX_2X8',
`SectionVendorTuples."'N_MATRIX_2X8($1)`_tuples_uuid" {'
`	tokens "sof_comp_tokens"'
`	tuples."uuid" {'
`		SOF_TKN_COMP_UUID'		STR(matrix_2x8_uuid)
`	}'
`}'
`SectionData."'N_MATRIX_2X8($1)`_data_uuid" {'
`	tuples "'N_MATRIX_2X8($1)`_tuples_uuid"'
`}'
`SectionVendorTuples."'N_MATRIX_2X8($1)`_tuples_w" {'
`	tokens "sof_comp_tokens"'
`	tuples."word" {'
`		SOF_TKN_COMP_PERIOD_SINK_COUNT'		STR($3)
`		SOF_TKN_COMP_PERIOD_SOURCE_COUNT'	STR($4)
`		SOF_TKN_COMP_CORE_ID'			STR($5)
`	}'
`}'
`SectionData."'N_MATRIX_2X8($1)`_data_w" {'
`	tuples "'N_MATRIX_2X8($1)`_tuples_w"'
`}'
`SectionVendorTuples."'N_MATRIX_2X8($1)`_tuples_str" {'
`	tokens "sof_comp_tokens"'
`	tuples."string" {'
`		SOF_TKN_COMP_FORMAT'	STR($2)
`	}'
`}'
`SectionData."'N_MATRIX_2X8($1)`_data_str" {'
`	tuples "'N_MATRIX_2X8($1)`_tuples_str"'
`}'
`SectionVendorTuples."'N_MATRIX_2X8($1)`_tuples_str_type" {'
`	tokens "sof_process_tokens"'
`	tuples."string" {'
`		SOF_TKN_PROCESS_TYPE'	"MATRIX_2X8"
`	}'
`}'
`SectionData."'N_MATRIX_2X8($1)`_data_str_type" {'
`	tuples "'N_MATRIX_2X8($1)`_tuples_str_type"'
`}'
`SectionWidget."'N_MATRIX_2X8($1)`" {'
`	index "'PIPELINE_ID`"'
`	type "effect"'
`	no_pm "true"'
`	data ['
`		"'N_MATRIX_2X8($1)`_data_uuid"'
`		"'N_MATRIX_2X8($1)`_data_w"'
`		"'N_MATRIX_2X8($1)`_data_str"'
`		"'N_MATRIX_2X8($1)`_data_str_type"'
`	]'
`	mixer ['
		$6
`	]'
`}')

divert(0)dnl
