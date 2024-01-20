#!/usr/bin/env bash

. ./cmd.sh
. ./path.sh
set -e
stage=5
stop_stage=100
skip_stages=0

. parse_options.sh
if [ ${stage} -le 1 ] && [ ${stop_stage} -ge 1 ] && ! [[ " ${skip_stages} " =~ [[:space:]]1[[:space:]] ]]; then
	echo "extract feature for train_960"
# at stage 12, align tran_960
steps/align_fmllr.sh --nj 40 --cmd "$train_cmd" \
	data/train_960 data/lang_nosp \
	exp/tri3b exp/tri3b_ali_960

# generate transition-id for each frame
for i in  exp/tri3b_ali_960/ali.*.gz;
do ali-to-pdf exp/tri3b/final.mdl \
	"ark,t:gunzip -c $i|" ark,t:${i%.gz}.pdf;
done;
cd exp/tri3b_ali_960
cat ali*.pdf > tri3b_960_pdf_alignment
fi

if [ ${stage} -le 2 ] && [ ${stop_stage} -ge 2 ] && ! [[ " ${skip_stages} " =~ [[:space:]]2[[:space:]] ]]; then
	echo "extract feature for train_100"
	target_folder=exp/tri3b_ali_clean_100
	for i in ${target_folder}/ali.*.gz;
	do ali-to-pdf ${target_folder}/final.mdl \
	       "ark,t:gunzip -c $i|" ark,t:${i%.gz}.pdf;
	done
	
	# merge file
	cat ${target_folder}/ali*.pdf > ${target_folder}/tri3b_clean_100_pdf_alignment
fi

if [ ${stage} -le 3 ] && [ ${stop_stage} -ge 3 ] && ! [[ " ${skip_stages} " =~ [[:space:]]3[[:space:]] ]]; then
	echo "extract force-alogned feature for train dev and test dataseti"
	test_sets="test_clean test_other dev_clean dev_other"
	train_set="train_clean_100"
	_dsets="${test_sets} ${train_set}"

	for dset in ${_dsets}; do
		echo "generate alignment for ${dset}"
		steps/align_fmllr.sh --nj 4 --cmd "$train_cmd" \
			data/$dset data/lang_nosp \
			exp/tri4b_2500 exp/tri4b_2500/align_${dset}
		target_folder=exp/tri4b_2500/align_${dset}

		echo "extact pdf-id"		
		for i in ${target_folder}/ali.*.gz;
		do ali-to-pdf ${target_folder}/final.mdl \
	       		"ark,t:gunzip -c $i|" ark,t:${i%.gz}.pdf;
		done
		cat ${target_folder}/ali*.pdf > ${target_folder}/tri4b_2500_${dset}_align_pdf_alignment

	done

fi
phone_lang=data/phone_lang
if [ ${stage} -le 4 ] && [ ${stop_stage} -ge 4 ] && ! [[ " ${skip_stages} " =~ [[:space:]]4[[:space:]] ]]; then
	lang=data/lang_nosp
	alidir=exp/tri4b_2500/align_train_clean_100
	# make a phone language G.fst and L.fst
	utils/lang/make_phone_bigram_lang.sh $lang $alidir $phone_lang
fi
num_leaves=4200
if [ ${stage} -le 5 ] && [ ${stop_stage} -ge 5 ] && ! [[ " ${skip_stages} " =~ [[:space:]]5[[:space:]] ]]; then
	echo "decode_fmllr extract feature for dev and test dataset"
	test_sets="test_clean test_other dev_clean dev_other"
	train_set="train_clean_100"
	_dsets="${train_set} ${test_sets}"
	#utils/mkgraph.sh data/lang_test_tgsmall \
	#	exp/tri4b_2500 exp/tri4b_2500/graph_tgsmall
	# make graph using the phone language
	utils/mkgraph.sh $phone_lang exp/tri4b_${num_leaves} exp/tri4b_${num_leaves}/graph_phone_bg
	_nj=20
	for dset in ${_dsets}; do
		echo " step 1: generate lattice for ${dset}"
		steps/decode_fmllr.sh --nj ${_nj} --cmd "$decode_cmd" \
			--skip_scoring "true" \
			exp/tri4b_${num_leaves}/graph_phone_bg \
			data/$dset exp/tri4b_${num_leaves}/decode_phonelm_${dset}
		target_folder=exp/tri4b_${num_leaves}/decode_phonelm_${dset}
		
		echo "step 2: generate the 1-bet path through lattices"
	
		for i in $(seq 1 ${_nj});
		do echo $i;
		   lattice-best-path "ark,t:gunzip -c $target_folder/lat.$i.gz|" \
                        "ark,t:|int2sym.pl -f 2- $phone_lang/words.txt > $target_folder/text.$i" \
			"ark:|gzip -c >$target_folder/ali.$i.gz" >2/dev/null || exit 1;
		done
		

		echo "step 3: extact pdf-id"		
		for i in ${target_folder}/ali.*.gz;
		do ali-to-pdf exp/tri4b_${num_leaves}/final.mdl \
	       		"ark,t:gunzip -c $i|" ark,t:${i%.gz}.pdf;
		done
		cat ${target_folder}/ali*.pdf > ${target_folder}/tri4b_${num_leaves}_${dset}_decode_pdf_alignment

	
	done

fi

#if [ ${stage} -le 5 ] && [ ${stop_stage} -ge 5 ] && ! [[ " ${skip_stages} " =~ [[:space:]]4[[:space:]] ]]; then
#	echo "scoring dev and test dataset without lm"
#	test_sets="test_clean test_other dev_clean dev_other"
#	train_set="train_clean_100"
#	_dsets=${test_sets}
	#utils/mkgraph.sh data/lang_test_tgsmall \
	#	exp/tri4b exp/tri4b/graph_tgsmall
#	_nj=4
#	for dset in ${_dsets}; do
#		echo " step 1: generate lattice for ${dset}"
#		steps/decode_fmllr.sh --nj ${_nj} --cmd "$decode_cmd" \
#			--skip_scoring "false" \
#			exp/tri4b/graph_tgsmall \
#			data/$dset exp/tri4b/decode_tgsmall_${dset}
	
#	done

#fi
		




