#!/usr/bin/env bash


# Set this to somewhere where you want to put your data, or where
# someone else has already put it.  You'll want to change this
# if you're not on the CLSP grid.
data=/export/a15/vpanayotov/data

# base url for downloads.
data_url=www.openslr.org/resources/12
lm_url=www.openslr.org/resources/11
mfccdir=mfcc
stage=9 # start from stage 6
stop_stage=12
skip_stages="4 5"
skip_train=false # if true, skip the training stages, just run the decoding stages, which is stage 13

feat_type=wav2vec2  #lda80_wavlm #wavlm
datadir=data/${feat_type} # to store the scp file
expdir=exp/${feat_type}_1000beam_nodelta_trans_monostate # to store the experiment
featdir=feat/${feat_type} # to store the feature itself
langdir=data/${feat_type}/lang_nosp_monostate # the language model folder, contains phones.txt, words.txt, topo, L.fst, etc.
n_beam=100
n_retry_beam=1000

# setup the train, dev and test set
train_set="train"
#train_dev="dev"
test_sets="test_clean test_other dev_clean dev_other test_1h"


. ./cmd.sh
. ./path.sh
. parse_options.sh



# you might not want to do this for interactive shells.
set -e

if $skip_train; then
  skip_stages+=" 8 9 10 11 12 14"
fi
echo "skip stages: ${skip_stages}"

if [ ${stage} -le 1 ] && [ ${stop_stage} -ge 1 ] && ! [[ " ${skip_stages} " =~ [[:space:]]1[[:space:]] ]]; then
  # download the data.  Note: we're using the 100 hour setup for
  # now; later in the script we'll download more and use it to train neural
  # nets.
  for part in dev-clean test-clean dev-other test-other train-clean-100; do
    local/download_and_untar.sh $data $data_url $part
  done


  # download the LM resources
  local/download_lm.sh $lm_url data/local/lm
fi

if [ ${stage} -le 2 ] && [ ${stop_stage} -ge 2 ] && ! [[ " ${skip_stages} " =~ [[:space:]]2[[:space:]] ]]; then
  # format the data as Kaldi data directories
  for part in dev-clean test-clean dev-other test-other train-clean-100; do
    # use underscore-separated names in data directories.
    local/data_prep.sh $data/LibriSpeech/$part data/$(echo $part | sed s/-/_/g)
  done
fi

## Optional text corpus normalization and LM training
## These scripts are here primarily as a documentation of the process that has been
## used to build the LM. Most users of this recipe will NOT need/want to run
## this step. The pre-built language models and the pronunciation lexicon, as
## well as some intermediate data(e.g. the normalized text used for LM training),
## are available for download at http://www.openslr.org/11/
#local/lm/train_lm.sh $LM_CORPUS_ROOT \
#  data/local/lm/norm/tmp data/local/lm/norm/norm_texts data/local/lm

## Optional G2P training scripts.
## As the LM training scripts above, this script is intended primarily to
## document our G2P model creation process
#local/g2p/train_g2p.sh data/local/dict/cmudict data/local/lm

if [ ${stage} -le 3 ] && [ ${stop_stage} -ge 3 ] && ! [[ " ${skip_stages} " =~ [[:space:]]3[[:space:]] ]]; then
  # when the "--stage 3" option is used below we skip the G2P steps, and use the
  # lexicon we have already downloaded from openslr.org/11/
#  local/prepare_dict.sh --stage 3 --nj 30 --cmd "$train_cmd" \
#   $datadir/local/lm $datadir/local/lm $datadir/local/dict_nosp

  utils/prepare_lang.sh --num-sil-states 1 --num-nonsil-states 1 \
      $datadir/local/dict_nosp \
    "<UNK>" $datadir/local/lang_tmp_nosp $langdir #$datadir/lang_nosp
#
#  local/format_lms.sh --src-dir $datadir/lang_nosp $datadir/local/lm
fi

if [ ${stage} -le 4 ] && [ ${stop_stage} -ge 4 ] && ! [[ " ${skip_stages} " =~ [[:space:]]4[[:space:]] ]]; then
  # Create ConstArpaLm format language model for full 3-gram and 4-gram LMs
  utils/build_const_arpa_lm.sh data/local/lm/lm_tglarge.arpa.gz \
    data/lang_nosp data/lang_nosp_test_tglarge
  utils/build_const_arpa_lm.sh data/local/lm/lm_fglarge.arpa.gz \
    data/lang_nosp data/lang_nosp_test_fglarge
fi

if [ ${stage} -le 5 ] && [ ${stop_stage} -ge 5 ] && ! [[ " ${skip_stages} " =~ [[:space:]]5[[:space:]] ]]; then
  # spread the mfccs over various machines, as this data-set is quite large.
  if [[  $(hostname -f) ==  *.clsp.jhu.edu ]]; then
    mfcc=$(basename mfccdir) # in case was absolute pathname (unlikely), get basename.
    utils/create_split_dir.pl /export/b{02,11,12,13}/$USER/kaldi-data/egs/librispeech/s5/$mfcc/storage \
     $mfccdir/storage
  fi
fi


if [ ${stage} -le 6 ] && [ ${stop_stage} -ge 6 ] && ! [[ " ${skip_stages} " =~ [[:space:]]6[[:space:]] ]]; then
  for part in dev_clean test_clean dev_other test_other train_clean_100; do
    if false; then
    #steps/make_mfcc.sh --cmd "$train_cmd" --nj 40 data/$part exp/make_mfcc/$part $mfccdir
    utils/copy_data_dir.sh --validate_opts --non-print "data/${part}" "${datadir}/${part}"
    # copy feat_pca80.scp to feat_pca80_wavlm.scp from the source directory to the target directory
    # and add the lbi before each line
    source=/export/fs05/mliu121/espnet_data/librispeech_100_asr2/dump/extracted/wavlm_large/layer21/${part}/feat_pca80.scp
    #cp ${source} ${datadir}/${part}/feats.scp
    target=${datadir}/${part}/feats.scp
    # add the lbi on each line of the feats.scp
    if [ -f ${target} ]; then
      rm ${target}
    fi
    while IFS= read -r line; do
      echo "lbi-${line}" >> ${target}
    done < ${source}

    # copy the utt2num_frames from the source directory to the target directory
    source=/export/fs05/mliu121/espnet_data/librispeech_100_asr2/dump/extracted/wavlm_large/layer21/${part}/utt2num_frames
    target=${datadir}/${part}/utt2num_frames
    if [ -f ${target} ]; then
      rm ${target}
    fi
    while IFS= read -r line; do
      echo "lbi-${line}" >> ${target}
    done < ${source}

    # rewrite the frame_shift file is 0.02
    if [ -f ${datadir}/${part}/frame_shift ]; then
      rm ${datadir}/${part}/frame_shift
    fi
    echo "0.02" >> ${datadir}/${part}/frame_shift
    fi
    # if fake, then no cmvn is applied
    steps/compute_cmvn_stats.sh --fake ${datadir}/${part} ${expdir}/make_cmvn/${part} ${featdir}
  done
fi

if [ ${stage} -le 7 ] && [ ${stop_stage} -ge 7 ] && ! [[ " ${skip_stages} " =~ [[:space:]]7[[:space:]] ]]; then
  # Make some small data subsets for early system-build stages.  Note, there are 29k
  # utterances in the train_clean_100 directory which has 100 hours of data.
  # For the monophone stages we select the shortest utterances, which should make it
  # easier to align the data from a flat start.

  #utils/subset_data_dir.sh --shortest data/train_clean_100 2000 data/train_2kshort
  #utils/subset_data_dir.sh data/train_clean_100 5000 data/train_5k
  #utils/subset_data_dir.sh data/train_clean_100 10000 data/train_10k

  # now for the challenge dataset, there are 152k utterances in the train directory
  # which about 100+284 hours of data, 4 times of the librispeech 100 hours data

  utils/subset_data_dir.sh --shortest ${datadir}/$train_set 8000 ${datadir}/train_8kshort
  utils/subset_data_dir.sh ${datadir}/$train_set 20000 ${datadir}/train_20k
  utils/subset_data_dir.sh ${datadir}/$train_set 40000 ${datadir}/train_40k
fi

if [ ${stage} -le 8 ] && [ ${stop_stage} -ge 8 ] && ! [[ " ${skip_stages} " =~ [[:space:]]8[[:space:]] ]]; then
  # train a monophone system, the defualt totgauss is 1000
#  steps/train_mono.sh --boost-silence 1.25 --nj 20 --cmd "$train_cmd" \
#                      data/train_2kshort data/lang_nosp exp/mono
# we use train_mono_nodelta.sh instead of train_mono.sh, because we don't need delta features for the wavlm
   steps/train_mono_nodelta.sh --boost-silence 1.25 --nj 10 --cmd "$train_cmd" \
	               --initial_beam 10 --regular_beam ${n_beam} --retry_beam ${n_retry_beam} \
                       ${datadir}/train_8kshort ${langdir} ${expdir}/mono

fi

if [ ${stage} -le 9 ] && [ ${stop_stage} -ge 9 ] && ! [[ " ${skip_stages} " =~ [[:space:]]9[[:space:]] ]]; then
  # align the train set using the monophone model
#  steps/align_si_nodelta.sh --boost-silence 1.25 --nj 10 --cmd "$train_cmd" \
#		                --beam ${n_beam} --retry_beam ${n_retry_beam} \
#                    ${datadir}/$train_set ${langdir} ${expdir}/mono ${expdir}/mono_ali_$train_set
  # retrain
  steps/train_mono2_nodelta.sh --boost-silence 1.25 --nj 10 --cmd "$train_cmd" \
                  --stage 0 \
                 --realign_iters "10 20 30" --num_iters 35 \
                 --num_iters 35  --totgauss 2000 \
	               --regular_beam ${n_beam} --retry_beam ${n_retry_beam} \
                       ${datadir}/$train_set ${langdir} ${expdir}/mono_ali_$train_set ${expdir}/mono ${expdir}/mono2

fi


if [ ${stage} -le 10 ] && [ ${stop_stage} -ge 10 ] && ! [[ " ${skip_stages} " =~ [[:space:]]10[[:space:]] ]]; then
  echo "build the unigram uniform phone-level language model"
  # build the bigram phone-level Language model
  phone_lang=${datadir}/phone_lang_monostate
  #lang=data/lang_nosp replace by the ${langdir}
  alidir=${expdir}/mono_ali_$train_set
  utils/lang/make_phone_bigram_lang.sh ${langdir} $alidir $phone_lang

  # decode using the tri4b model and generate the decoding alignment
  graphdir=${expdir}/mono2/graph_phone_bg
  utils/mkgraph.sh $phone_lang \
                   ${expdir}/mono2 ${graphdir}
  if "${skip_train}"; then
    _dsets="${test_sets}"
  else
    _dsets="${test_sets} ${train_set}"
  fi
for test in ${_dsets}; do
 #for test in train_clean_100_sp1.1; do
  #for test in train_clean_100 test_clean test_other dev_clean dev_other; do
      (
      echo "step 1: decode the ${test} set,generate the lattice "
      skip_scoring=true
      _nj=20

      # no delta features and no transform-feats
      acwt=0.083333 # Acoustic weight used in getting fMLLR transforms, and also in lattice generation.
#     # may be change the number of beam and the number of max-active to achieve more accurate decoding
      target_folder=${expdir}/mono2/decode_phonelm_${test}
      model=${expdir}/mono2/final.mdl
      steps/decode_nodelta.sh --nj ${_nj} --cmd "$decode_cmd" \
                            --skip_scoring $skip_scoring \
                            --acwt $acwt --beam 16 \
                            --max-active 7000 \
                            --model ${model} \
                            ${graphdir} ${datadir}/${test} \
                            ${target_folder} || exit 1;
      echo "step 2: generate the 1-bet path through lattices, and convert it to gaussian-level posterior"

      #combine the lattice-best-path and ali-to-post, gmm-post-to-gpost with a pipe, so the output of the first command is the input of the second command
      sdata=${datadir}/${test}/split${_nj}
      cmvn_opts=`cat ${expdir}/mono2/cmvn_opts 2>/dev/null`
      feats="ark,s,cs:apply-cmvn --norm-vars=false --utt2spk=ark:${sdata}/JOB/utt2spk scp:${sdata}/JOB/cmvn.scp scp:${sdata}/JOB/feats.scp ark:- |"

      $train_cmd JOB=1:$_nj $target_folder/log/ali_pdf.JOB.log \
         lattice-best-path "ark,t:gunzip -c $target_folder/lat.JOB.gz|" \
              "ark,t:|int2sym.pl -f 2- $phone_lang/words.txt > $target_folder/text.JOB" ark:- \| \
              ali-to-post ark:- ark:- \| \
              gmm-post-to-gpost $model "$feats" ark:- ark,t:${target_folder}/gpost.JOB || exit 1;
      echo "step3: covert the gpost to gaussian-id"
      #cat ${target_folder}/ali*.pdf > ${target_folder}/tri4b_${num_leaves}_${test}_decode_pdf_alignment
      cat ${target_folder}/gpost.* > ${target_folder}/mono2_${test}_decode_gpost
      # call the convert_gpost_to_gaussid.py to convert the gpost to gaussid
      python convert_gpost_pid.py ${target_folder}/../final.mdl.txt ${target_folder}/mono2_${test}_decode_gpost ${target_folder}/mono2_${test}_decode_gaussid
      ) &
  done
fi

if [ ${stage} -le 11 ] && [ ${stop_stage} -ge 11 ] && ! [[ " ${skip_stages} " =~ [[:space:]]11[[:space:]] ]]; then
  echo "score the phone error rate of the decoded result using phone-level LM"
  # to calculate this term, we first need to generate the phoneme sequence reference for each test data
  # write a python script -- apply_map.py to convert the text to the phoneme sequence
  # score the phone error rate
  for test in ${test_sets}; do
    (
    echo "score the phone error rate for ${test}"
    local/score_phoneme.sh ${datadir}/${test} ${expdir}/mono2/graph_phone_bg ${expdir}/mono2/decode_phonelm_${test}
    ) &
  done
  fi


<<COMMENT
if [ ${stage} -le 14 ] && [ ${stop_stage} -ge 14 ] && ! [[ " ${skip_stages} " =~ [[:space:]]14[[:space:]] ]]; then
  # This stage is for nnet2 training on 100 hours; we're commenting it out
  # as it's deprecated.
  # align train_clean_100 using the tri4b model
  steps/align_fmllr.sh --nj 30 --cmd "$train_cmd" \
    data/train_clean_100 data/lang exp/tri4b exp/tri4b_ali_clean_100

  # This nnet2 training script is deprecated.
  local/nnet2/run_5a_clean_100.sh
fi


if [ $stage -le 15 ] && [ ${stop_stage} -ge 15 ] && ! [[ " ${skip_stages} " =~ [[:space:]]15[[:space:]] ]]; then
  local/download_and_untar.sh $data $data_url train-clean-360

  # now add the "clean-360" subset to the mix ...
  local/data_prep.sh \
    $data/LibriSpeech/train-clean-360 data/train_clean_360
  steps/make_mfcc.sh --cmd "$train_cmd" --nj 40 data/train_clean_360 \
                     exp/make_mfcc/train_clean_360 $mfccdir
  steps/compute_cmvn_stats.sh \
    data/train_clean_360 exp/make_mfcc/train_clean_360 $mfccdir

  # ... and then combine the two sets into a 460 hour one
  utils/combine_data.sh \
    data/train_clean_460 data/train_clean_100 data/train_clean_360
fi

if [ $stage -le 16 ] && [ ${stop_stage} -ge 16 ] && ! [[ " ${skip_stages} " =~ [[:space:]]16[[:space:]] ]]; then
  # align the new, combined set, using the tri4b model
  steps/align_fmllr.sh --nj 40 --cmd "$train_cmd" \
                       data/train_clean_460 data/lang exp/tri4b exp/tri4b_ali_clean_460

  # create a larger SAT model, trained on the 460 hours of data.
  steps/train_sat.sh  --cmd "$train_cmd" 5000 100000 \
                      data/train_clean_460 data/lang exp/tri4b_ali_clean_460 exp/tri5b
fi


# The following command trains an nnet3 model on the 460 hour setup.  This
# is deprecated now.
## train a NN model on the 460 hour set
#local/nnet2/run_6a_clean_460.sh

if [ $stage -le 17 ] && [ ${stop_stage} -ge 17 ] && ! [[ " ${skip_stages} " =~ [[:space:]]17[[:space:]] ]]; then
  # prepare the remaining 500 hours of data
  local/download_and_untar.sh $data $data_url train-other-500

  # prepare the 500 hour subset.
  local/data_prep.sh \
    $data/LibriSpeech/train-other-500 data/train_other_500
  steps/make_mfcc.sh --cmd "$train_cmd" --nj 40 data/train_other_500 \
                     exp/make_mfcc/train_other_500 $mfccdir
  steps/compute_cmvn_stats.sh \
    data/train_other_500 exp/make_mfcc/train_other_500 $mfccdir

  # combine all the data
  utils/combine_data.sh \
    data/train_960 data/train_clean_460 data/train_other_500
fi

if [ $stage -le 18 ] && [ ${stop_stage} -ge 18 ] && ! [[ " ${skip_stages} " =~ [[:space:]]18[[:space:]] ]]; then
  steps/align_fmllr.sh --nj 40 --cmd "$train_cmd" \
                       data/train_960 data/lang exp/tri5b exp/tri5b_ali_960

  # train a SAT model on the 960 hour mixed data.  Use the train_quick.sh script
  # as it is faster.
  steps/train_quick.sh --cmd "$train_cmd" \
                       7000 150000 data/train_960 data/lang exp/tri5b_ali_960 exp/tri6b

  # decode using the tri6b model
  utils/mkgraph.sh data/lang_test_tgsmall \
                   exp/tri6b exp/tri6b/graph_tgsmall
  for test in test_clean test_other dev_clean dev_other; do
      steps/decode_fmllr.sh --nj 20 --cmd "$decode_cmd" \
                            exp/tri6b/graph_tgsmall data/$test exp/tri6b/decode_tgsmall_$test
      steps/lmrescore.sh --cmd "$decode_cmd" data/lang_test_{tgsmall,tgmed} \
                         data/$test exp/tri6b/decode_{tgsmall,tgmed}_$test
      steps/lmrescore_const_arpa.sh \
        --cmd "$decode_cmd" data/lang_test_{tgsmall,tglarge} \
        data/$test exp/tri6b/decode_{tgsmall,tglarge}_$test
      steps/lmrescore_const_arpa.sh \
        --cmd "$decode_cmd" data/lang_test_{tgsmall,fglarge} \
        data/$test exp/tri6b/decode_{tgsmall,fglarge}_$test
  done
fi


if [ $stage -le 19 ] && [ ${stop_stage} -ge 19 ] && ! [[ " ${skip_stages} " =~ [[:space:]]19[[:space:]] ]]; then
  # this does some data-cleaning. The cleaned data should be useful when we add
  # the neural net and chain systems.  (although actually it was pretty clean already.)
  local/run_cleanup_segmentation.sh
fi

# steps/cleanup/debug_lexicon.sh --remove-stress true  --nj 200 --cmd "$train_cmd" data/train_clean_100 \
#    data/lang exp/tri6b data/local/dict/lexicon.txt exp/debug_lexicon_100h

# #Perform rescoring of tri6b be means of faster-rnnlm
# #Attention: with default settings requires 4 GB of memory per rescoring job, so commenting this out by default
# wait && local/run_rnnlm.sh \
#     --rnnlm-ver "faster-rnnlm" \
#     --rnnlm-options "-hidden 150 -direct 1000 -direct-order 5" \
#     --rnnlm-tag "h150-me5-1000" $data data/local/lm

# #Perform rescoring of tri6b be means of faster-rnnlm using Noise contrastive estimation
# #Note, that could be extremely slow without CUDA
# #We use smaller direct layer size so that it could be stored in GPU memory (~2Gb)
# #Suprisingly, bottleneck here is validation rather then learning
# #Therefore you can use smaller validation dataset to speed up training
# wait && local/run_rnnlm.sh \
#     --rnnlm-ver "faster-rnnlm" \
#     --rnnlm-options "-hidden 150 -direct 400 -direct-order 3 --nce 20" \
#     --rnnlm-tag "h150-me3-400-nce20" $data data/local/lm


if [ $stage -le 20 ] && [ ${stop_stage} -ge 20 ] && ! [[ " ${skip_stages} " =~ [[:space:]]20[[:space:]] ]]; then
  # train and test nnet3 tdnn models on the entire data with data-cleaning.
  local/chain/run_tdnn.sh # set "--stage 11" if you have already run local/nnet3/run_tdnn.sh
fi

# The nnet3 TDNN recipe:
# local/nnet3/run_tdnn.sh # set "--stage 11" if you have already run local/chain/run_tdnn.sh

# # train models on cleaned-up data
# # we've found that this isn't helpful-- see the comments in local/run_data_cleaning.sh
# local/run_data_cleaning.sh

# # The following is the current online-nnet2 recipe, with "multi-splice".
# local/online/run_nnet2_ms.sh

# # The following is the discriminative-training continuation of the above.
# local/online/run_nnet2_ms_disc.sh

# ## The following is an older version of the online-nnet2 recipe, without "multi-splice".  It's faster
# ## to train but slightly worse.
# # local/online/run_nnet2.sh

COMMENT



