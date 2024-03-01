# convert the guassian posteriors to gaussian id by selecting the maximum posterior
# Usage: python convert_gpost_pid.py <model> <gpost> <gpost_pid>
# input: gpost
# with the format: utt_id posterior for first frame
#                  posterior for second frame
#                  ...
#      the format of each posterior is: 1 pdf-id [posterior1_1, posterior1_2, ...] for each mixture

# input: model (i.e. final.mdl.txt)
# with the format <DIMENSION> 1024 <NUMPDFS> 42 <DiaGMM> <GCONSTS> [] ...   </DiaGMM>
# output: gpost_pid
# with the format: utt_id a list of pdf-id for each frame

import sys
import numpy as np

def read_mdl(model):
    # num_mixtures is a list, each element is the number of mixtures for each pdf
    num_mixtures = []
    with open(model, 'r') as f:
        for line in f.readlines():
            if line.startswith("<DIMENSION>"):
                # <DIMENSION> 1024 <NUMPDFS> 41 <DiagGMM>
                dim = int(line.strip().split()[1])
                num_pdfs = int(line.strip().split()[3])
            elif line.startswith("<GCONSTS>"):
                #<GCONSTS>  [ -13755.16 -3168.719 -3766.174 -3066.913 -3077.927 -3403.586 -3335.324 -3032.826 -3199.674 ]
                posterior = np.array(line.strip().split()[2:-1]).astype(np.float64)
                num_mixtures.append(len(posterior))
    # double check, the length of num_mixtures should be equal to num_pdfs
    assert len(num_mixtures) == num_pdfs
    return num_pdfs, num_mixtures, dim

def write_gpost_pid(gpost, gpost_pid,num_pdfs, num_mixtures):
    #lbi-1034-121119-0021 235 1 0  [ 1 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 ] first frame
    # 1 0  [ 0 0 1 0 0 0 0 0 0 0 0 0 0 0 0 0 0 ] second frame
    # 1 0  [ 0 0 0 0 0 0 0 0 0 1 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 ] third frame
    # ...
    # lbi-1034-121119-0035 141 1 0  [ 1 0 0 0 0 0 0 0 0 0 0 0 0 0 0 ] first frame
    # ...

    with open(gpost, 'r') as f_gpost, open(gpost_pid, 'w') as f_gpost_pid:
        line=f_gpost.readline()
        while line:
            assert line.startswith("lbi-") or line.startswith("sp") or line.startswith("sw") or line.startswith("en")
            if line.startswith("lbi-") or line.startswith("sp") or line.startswith("sw") or line.startswith("en"):
                #print("line: ", line)
                # this means we have a new utterance
                utt_id = line.strip().split()[0]
                num_frames = int(line.strip().split()[1])
                pdf_id = int(line.strip().split()[3]) # the current pdf-id for this frame
                list_pdf_id = []
                # first frame is at the same line
                posterior = np.array(line.strip().split('[')[1].split()[:-1]).astype(np.float64)

                # double check, the length of posterior should be equal to the number of mixtures for this pdf
                assert len(posterior) == num_mixtures[pdf_id]
                # find the maximum posterior for the first frame
                max_posterior = np.argmax(posterior)
                list_pdf_id.append(max_posterior)
                # the rest of the frames are in the next lines
                for i in range(num_frames-1):
                    line = f_gpost.readline()
                    #print("line: ", line)
                    pdf_id = int(line.strip().split()[1]) # the current pdf-id for this frame
                    posterior = np.array(line.strip().split('[')[1].split()[:-1]).astype(np.float64)
                    # double check, the length of posterior should be equal to the number of mixtures for this pdf
                    assert len(posterior) == num_mixtures[pdf_id]
                    # find the maximum posterior for the first frame
                    max_posterior_id = np.argmax(posterior)
                    # convert the max_posterior_id to the gaussian id based on the number of mixtures for each pdf
                    list_pdf_id.append(max_posterior_id + sum(num_mixtures[:pdf_id]))

                assert len(list_pdf_id) == num_frames
                # write the utt_id and the list of pdf-id for each frame
                f_gpost_pid.write(utt_id + ' ' + ' '.join([str(x) for x in list_pdf_id]) + '\n')

                # make sure that next line is empty
                assert f_gpost.readline() == '\n'
            line=f_gpost.readline()

def main():
    print(sys.argv)
    if len(sys.argv) != 4:
        print("Usage: python convert_gpost_pid.py <model> <gpost> <gpost_pid>")
        sys.exit(1)

    model = sys.argv[1]
    gpost = sys.argv[2]
    gpost_pid = sys.argv[3]
    print("model: ", model)
    print("gpost: ", gpost)
    print("gpost_pid: ", gpost_pid)

    # first read the final.mdl.txt, to get the number of pdfs, the number of mixtures for each pdf
    # and the dimension of the features
    num_pdfs, num_mixtures, dim = read_mdl(model)
    print("num_pdfs: ", num_pdfs)
    print("total number of mixtures: ", sum(num_mixtures))
    print("dim: ", dim)


    # read the gpost file, and convert it to gpost_pid
    write_gpost_pid(gpost, gpost_pid,num_pdfs, num_mixtures)


if __name__ == "__main__":
    main()
