#!/usr/bin/env nextflow

// Get sample info from sample sheet
// Minimum information that are needed in the sample sheet are SampleID, Gender and BAM file location (pointing to CRAM)
Channel.fromPath( file(params.sample_sheet) )
        .splitCsv(header: true, sep: '\t')
        .map{row ->
            def sample_id = row['SampleID']
            def bam_file = file(row['BAM'])
            return [ sample_id, bam_file ]
        }.set{samples}

ref_seq = Channel.fromPath(params.ref_seq).toList()

process log_tool_version {
    tag { "${params.project_name}.ltV" }
    echo true
    publishDir "${params.out_dir}/", mode: 'copy', overwrite: false
    label 'bwa_samtools'

    output:
    file("tool.version") into tool_version

    script:
    """
    samtools --version > tool.version
    """
}

process bam_to_cram {
    tag { "${params.project_name}.${sample_id}.btC" }
    memory { 4.GB * task.attempt }
    publishDir "${params.out_dir}/${sample_id}", mode: 'copy', overwrite: false
    label 'bwa_samtools'
    input:
    set val(sample_id), file(bam_file) from samples
    file (ref) from ref_seq

    output:
    set val(sample_id), file("${bam_file.baseName}.cram") into cram_file

    script:
    """
    samtools view \
    --reference ${ref} \
    --output-fmt cram,version=3.0 \
    -o ${bam_file.baseName}.cram  ${bam_file}
    """
}

cram_file.into{ cram_file_1; cram_file_2; cram_file_3 }

process index_cram {
    tag { "${params.project_name}.${sample_id}.iC" }
    memory { 4.GB * task.attempt }
    publishDir "${params.out_dir}/${sample_id}", mode: 'move', overwrite: false
    label 'bwa_samtools'
    input:
    set val(sample_id), file(cram_file) from cram_file_1

    output:
    set val(sample_id), file("${cram_file}.crai") into cram_index

    script:
    """
    samtools index  \
    ${cram_file} ${cram_file}.crai
    """
}

process run_flagstat {
    tag { "${params.project_name}.${sample_id}.rF" }
    memory { 4.GB * task.attempt }
    publishDir "${params.out_dir}/${sample_id}", mode: 'copy', overwrite: false
    label 'bwa_samtools'
    input:
    set val(sample_id), file(cram_file) from cram_file_2

    output:
    set val(sample_id), file("${cram_file}.flagstat") into cram_stats

    script:
    """
    samtools flagstat \
    -@ 1 \
    ${cram_file} > ${cram_file}.flagstat  \
    """
}

cram_file_3.mix(cram_index,cram_stats).groupTuple().set{cram_all}

process create_md5sum {
    tag { "${params.project_name}.${sample_id}.cMD5S" }
    memory { 4.GB * task.attempt }
    publishDir "${params.out_dir}/${sample_id}", mode: 'move', overwrite: false
    input:
    set val(sample_id), file(cram_file) from cram_all

    output:
    set val(sample_id), file(cram_file), file("${cram_file[0]}.md5"), file("${cram_file[1]}.md5") into cram_all_md5sum

    script:
    """
    md5sum ${cram_file[0]} > ${cram_file[0]}.md5
    md5sum ${cram_file[1]} > ${cram_file[1]}.md5
    """
}

workflow.onComplete {

    println ( workflow.success ? """
        Pipeline execution summary
        ---------------------------
        Completed at: ${workflow.complete}
        Duration    : ${workflow.duration}
        Success     : ${workflow.success}
        workDir     : ${workflow.workDir}
        exit status : ${workflow.exitStatus}
        """ : """
        Failed: ${workflow.errorReport}
        exit status : ${workflow.exitStatus}
        """
    )
}
