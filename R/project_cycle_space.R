#' Project data into the cell cycle pattern space
#'
#' Project mouse and human single cell RNAseq data into a cell cycle embedding by a pre-learned reference projection matrix.
#'
#' @param x A numeric matrix of **log-expression** values where rows are features and columns are cells.
#' Alternatively, a \linkS4class{SummarizedExperiment} or \linkS4class{SingleCellExperiment} containing such a matrix.
#' @param ... For the \code{inferCCStage} generic, additional arguments to pass to specific methods.
#' For the \linkS4class{SummarizedExperiment} and  \linkS4class{SingleCellExperiment} methods, additional arguments to pass to the ANY method.
#' @param exprs_values Integer scalar or string indicating which assay of \code{x} contains the **log-expression** values. Default: 'logcounts'
#' @param ref.m A custom reference projection matrix to project the new data, where rows are features and columns are dimensions.
#' Users need to use the same type of \code{gname}(or rownames of \code{x}) as for the \code{ref.m}.
#' If no custom ref.m is given, the internal reference \code{neuroRef} will be used.
#' @param gname Alternative rownames of \code{x}. If provided, this will be used to map genes within \code{x} with genes in \code{ref.m}.
#' If not provided, the rownames of \code{x} will be used instead. Default: NULL
#' @param gname.type The type of gene names as in \code{gname} or rownames of \code{x}. It can be either 'ENSEMBL' or 'SYMBOL'. If the user uses
#' custom \code{ref.m}, this value will have no effect. Default: 'ENSEMBL'
#' @param species The type of species in \code{x}. It can be either 'mouse' or 'human'. If the user uses
#' custom \code{ref.m}, this value will have no effect. Default: 'mouse'
#' @param AnnotationDb An AnnotationDb objects. If the user uses the internal reference to project human data,
#'  and provide rownames in the format of Ensembl IDs, this object will be used to map Ensembl IDs to gene SYMBOLs.
#'  If no AnnotationDb object being given, the function will use \code{\link[org.Hs.eg.db]{org.Hs.eg.db}}.
#' @param altexp String or integer scalar specifying an alternative experiment containing the input data.
#' @param name String specifying the name to be used to store the result in the \code{\link[SingleCellExperiment]{reducedDims}} of the output. Default: 'tricycleEmbedding'
#'
#' @details
#' The function will use pre-learned cell cycle pattern to project new data to show the cell cycle progression. If the user uses internal Neuropshere reference,
#' the expression values must be **log-transformed**. Besides, we would assume the input data has been already preprocessed, library size normalized at least.
#' The projection process is to take sum of weighted mean-centered expression of chosen genes, so the mean expression of a given gene could be affected without library size normalization.
#'
#' @return
#' If the input is a numeric matrix or a \linkS4class{SummarizedExperiment}, a projection matrix with rows cells and column dimensions will be returned.
#' The actual rotation matrix used to project the data is included in the attributes with name 'rotation'.
#'
#' For \linkS4class{SingleCellExperiment}, an updated \linkS4class{SingleCellExperiment} is returned containing projection matrix in \code{\link[SingleCellExperiment]{reducedDims}(..., name)}.
#'
#' @name project_cycle_space
#' @seealso
#' \code{\link{estimate_cycle_position}}, for inferring cell cycle position.
#'
#' @author Shijie C. Zheng
#'
#' @examples
#' neurosphere_example <- project_cycle_space(neurosphere_example)
#' reducedDimNames(neurosphere_example)
#' head(reducedDim(neurosphere_example, "tricycleEmbedding"))
#' plot(reducedDim(neurosphere_example, "tricycleEmbedding"))
#' names(attributes(reducedDim(neurosphere_example, "tricycleEmbedding")))
NULL




.project_cycle_space <- function(data.m, ref.m = NULL, gname = NULL, gname.type = c("ENSEMBL", "SYMBOL"), species = c("mouse", "human"), AnnotationDb = NULL) {
    species <- match.arg(species)
    gname.type <- match.arg(gname.type)

    if (!is.null(gname)) {
        rownames(data.m) <- gname
    }
    if (is.null(ref.m)) {
        message("No custom reference projection matrix provided. The ref learned from mouse Neuroshpere data will be used.")
        ref.m <- .getRotation(gname.type = gname.type, species = species)

        if (species == "human" & gname.type == "ENSEMBL") {
            message("As the reference data was learned from mouse, we will map the human ENSEMBL id to gene SYMBOL.")
            rownames(data.m) <- .humanSymbol(gname = rownames(data.m), AnnotationDb = AnnotationDb)
        }
    }
    .calProjection(data.m, ref.m)
}

.calProjection <- function(data.m, rotation.m) {
    genes <- intersect(rownames(data.m), rownames(rotation.m))

    if (length(genes) == 0) {
          stop("None genes found in new data. This could be caused by wrong input of rownames type.")
      }
    message(paste0("The number of projection genes found in the new data is ", length(genes), "."))

    rotation.m <- rotation.m[genes, ]
    data.m <- data.m[genes, ]
    projection.m <- scale(t(as.matrix(data.m)), center = TRUE, scale = FALSE) %*% rotation.m
    rownames(projection.m) <- colnames(data.m)
    colnames(projection.m) <- colnames(rotation.m)
    attr(projection.m, "rotation") <- rotation.m

    return(projection.m)
}

.getRotation <- function(gname.type, species) {
    rotation.m <- as.matrix(neuroRef[, seq_len(2)])
    if (species == "human") {
        rownames(rotation.m) <- neuroRef$SYMBOL
    } else {
        rownames(rotation.m) <- neuroRef[, tolower(gname.type)]
    }
    colnames(rotation.m) <- c("PC1", "PC2")
    return(rotation.m)
}

#' @importFrom  org.Hs.eg.db org.Hs.eg.db
#' @importFrom AnnotationDbi mapIds
#' @importMethodsFrom AnnotationDbi colnames get ncol nrow
.humanSymbol <- function(gname, AnnotationDb = NULL) {
    if (is.null(AnnotationDb)) {
        AnnotationDb <- org.Hs.eg.db::org.Hs.eg.db
        message("No AnnotationDb desginated. org.Hs.eg.db will be used to map Human ENSEMBL id to gene SYMBOL.")
    }
    SYMBOL <- AnnotationDbi::mapIds(AnnotationDb, keys = gname, columns = "SYMBOL", keytype = "ENSEMBL", multiVals = "first")
    return(SYMBOL)
}


#' @export
#' @rdname project_cycle_space
setMethod("project_cycle_space", "ANY", function(x, ref.m = NULL, gname = NULL, gname.type = c("ENSEMBL", "SYMBOL"), species = c("mouse", "human"), AnnotationDb = NULL) {
    .project_cycle_space(x, ref.m = ref.m, gname = gname, gname.type = gname.type, species = species, AnnotationDb = AnnotationDb)
})

#' @export
#' @rdname project_cycle_space
#' @importFrom SummarizedExperiment assay
setMethod("project_cycle_space", "SummarizedExperiment", function(x, ..., exprs_values = "logcounts") {
    .project_cycle_space(assay(x, exprs_values), ...)
})


#' @export
#' @rdname project_cycle_space
#' @importFrom SingleCellExperiment reducedDim<- altExp
#' @importFrom SummarizedExperiment assay
setMethod("project_cycle_space", "SingleCellExperiment", function(x, ..., exprs_values = "logcounts", altexp = NULL, name = "tricycleEmbedding") {
    if (!is.null(altexp)) {
        y <- altExp(x, altexp)
    } else {
        y <- x
    }
    reducedDim(x, name) <- .project_cycle_space(assay(y, exprs_values), ...)
    x
})
