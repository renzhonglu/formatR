#' Reformat R code while preserving blank lines and comments
#'
#' This function returns reformatted source code; it tries to preserve blank
#' lines and comments, which is different with \code{\link{parse}} and
#' \code{\link{deparse}}. It can also replace \code{=} with \code{<-} where
#' \code{=} means assignments, and reindent code by a specified number of spaces
#' (default is 4).
#' @param source a character string: location of the source code (default to be
#'   the clipboard; this means we can copy the code to clipboard and use
#'   \code{tidy.souce()} without specifying the argument \code{source})
#' @param comment whether to keep comments (\code{TRUE} by default)
#' @param blank whether to keep blank lines (\code{TRUE} by default)
#' @param arrow whether to replace the assign operator \code{=} with \code{<-}
#' @param brace.newline whether to put the left brace \code{\{} to a new line
#'   (default \code{FALSE})
#' @param indent number of spaces to indent the code (default 4)
#' @param output output to the console or a file using \code{\link{cat}}?
#' @param text an alternative way to specify the input: if it is \code{NULL},
#'   the function will read the source code from the \code{source} argument;
#'   alternatively, if \code{text} is a character vector containing the source
#'   code, it will be used as the input and the \code{source} argument will be
#'   ignored
#' @param width.cutoff passed to \code{\link{deparse}}: integer in [20, 500]
#'   determining the cutoff at which line-breaking is tried (default to be
#'   \code{getOption("width")})
#' @param ... other arguments passed to \code{\link{cat}}, e.g. \code{file}
#'   (this can be useful for batch-processing R scripts, e.g.
#'   \code{tidy_source(source = 'input.R', file = 'output.R')})
#' @return A list with components \item{text.tidy}{the reformatted code as a
#'   character vector} \item{text.mask}{the code containing comments, which are
#'   masked in assignments or with the weird operator}
#' @note Be sure to read the reference to know other limitations.
#' @author Yihui Xie <\url{http://yihui.name}> with substantial contribution
#'   from Yixuan Qiu <\url{http://yixuan.cos.name}>
#' @seealso \code{\link{parse}}, \code{\link{deparse}}
#' @references \url{http://yihui.name/formatR} (an introduction to this package,
#'   with examples and further notes)
#' @export
#' @example inst/examples/tidy.source.R
tidy_source = function(
  source = 'clipboard', comment = getOption('formatR.comment', TRUE),
  blank = getOption('formatR.blank', TRUE),
  arrow = getOption('formatR.arrow', FALSE),
  brace.newline = getOption('formatR.brace.newline', FALSE),
  indent = getOption('formatR.indent', 4),
  output = TRUE, text = NULL,
  width.cutoff = getOption('width'), ...
) {
  # compatibility with formatR <= v0.10
  if (is.logical(getOption('keep.comment'))) {
    warning("The option 'keep.comment' is deprecated; please use 'formatR.comment'")
    options(formatR.comment = getOption('keep.comment'))
  }
  if (is.logical(getOption('keep.blank.line'))) {
    warning("The option 'keep.blank.line' is deprecated; please use 'formatR.blank'")
    options(formatR.blank = getOption('keep.blank.line'))
  }
  if (is.logical(getOption('replace.assign'))) {
    warning("The option 'replace.assign' is deprecated; please use 'formatR.arrow'")
    options(formatR.arrow = getOption('replace.assign'))
  }
  if (is.logical(getOption('left.brace.newline'))) {
    warning("The option 'left.brace.newline' is deprecated; please use 'formatR.brace.newline'")
    options(formatR.brace.newline = getOption('left.brace.newline'))
  }
  if (is.numeric(getOption('reindent.spaces'))) {
    warning("The option 'reindent.spaces' is deprecated; please use 'formatR.indent'")
    options(formatR.indent = getOption('reindent.spaces'))
  }
  extra = list(...)
  if (is.logical(extra$keep.comment)) {
    warning("The argument 'keep.comment' is deprecated; please use 'comment'")
    comment = extra$keep.comment
    extra$keep.comment = NULL
  }
  if (is.logical(extra$keep.blank.line)) {
    warning("The argument 'keep.blank.line' is deprecated; please use 'blank'")
    blank = extra$keep.blank.line
    extra$keep.blank.line = NULL
  }
  if (is.logical(extra$replace.assign)) {
    warning("The argument 'replace.assign' is deprecated; please use 'arrow'")
    arrow = extra$replace.assign
    extra$replace.assign = NULL
  }
  if (is.logical(extra$left.brace.newline)) {
    warning("The argument 'left.brace.newline' is deprecated; please use 'brace.newline'")
    brace.newline = extra$left.brace.newline
    extra$left.brace.newline = NULL
  }
  if (is.numeric(extra$reindent.spaces)) {
    warning("The argument 'reindent.spaces' is deprecated; please use 'indent'")
    indent = extra$reindent.spaces
    extra$reindent.spaces = NULL
  }

  if (is.null(text)) {
    if (source == 'clipboard' && Sys.info()['sysname'] == 'Darwin') {
      source = pipe('pbpaste')
    }
  } else {
    source = textConnection(text); on.exit(close(source))
  }
  text = readLines(source, warn = FALSE)
  if (length(text) == 0L || all(grepl('^\\s*$', text))) {
    if (output) cat('\n', ...)
    return(list(text.tidy = text, text.mask = text))
  }
  if (blank && R3) {
    one = paste(text, collapse = '\n') # record how many line breaks before/after
    n1 = attr(regexpr('^\n*', one), 'match.length')
    n2 = attr(regexpr('\n*$', one), 'match.length')
  }
  if (comment) text = mask_comments(text, width.cutoff, blank)
  text.mask = tidy_block(text, width.cutoff, arrow && length(grep('=', text)))
  text.tidy = if (comment) unmask_source(text.mask) else text.mask
  text.tidy = reindent_lines(text.tidy, indent)
  if (brace.newline) text.tidy = move_leftbrace(text.tidy)
  # restore new lines in the beginning and end
  if (blank && R3) text.tidy = c(rep('', n1), text.tidy, rep('', n2))
  if (output) do.call(cat, c(list(paste(text.tidy, collapse = '\n'), '\n'), extra))
  invisible(list(text.tidy = text.tidy, text.mask = text.mask))
}

## if you have variable names like this in your code, then you really beat me...
begin.comment = '.BeGiN_TiDy_IdEnTiFiEr_HaHaHa'
end.comment = '.HaHaHa_EnD_TiDy_IdEnTiFiEr'
pat.comment = sprintf('invisible\\("\\%s|\\%s"\\)', begin.comment, end.comment)
mat.comment = sprintf('invisible\\("\\%s([^"]*)\\%s"\\)', begin.comment, end.comment)
inline.comment = ' %InLiNe_IdEnTiFiEr%[ ]*"([ ]*#[^"]*)"'
blank.comment = sprintf('invisible("%s%s")', begin.comment, end.comment)

# wrapper around parse() and deparse()
tidy_block = function(text, width = getOption('width'), arrow = FALSE) {
  exprs = parse_only(text)
  if (length(exprs) == 0) return(character(0))
  exprs = if (arrow) replace_assignment(exprs) else as.list(exprs)
  sapply(exprs, function(e) paste(base::deparse(e, width), collapse = '\n'))
}

# Restore the real source code from the masked text
unmask_source = function(text.mask) {
  if (length(text.mask) == 0) return(text.mask)
  ## if the comments were separated into the next line, then remove '\n' after
  ##   the identifier first to move the comments back to the same line
  text.mask = gsub('%InLiNe_IdEnTiFiEr%[ ]*\n', '%InLiNe_IdEnTiFiEr%', text.mask)
  ## move 'else ...' back to the last line
  text.mask = gsub('\n\\s*else', ' else', text.mask)
  if (R3) {
    if (any(grepl('\\\\\\\\', text.mask)) && (any(grepl(mat.comment, text.mask)) ||
          any(grepl(inline.comment, text.mask)))) {
      m = gregexpr(mat.comment, text.mask)
      regmatches(text.mask, m) = lapply(regmatches(text.mask, m), restore_bs)
      m = gregexpr(inline.comment, text.mask)
      regmatches(text.mask, m) = lapply(regmatches(text.mask, m), restore_bs)
    }
  } else text.mask = restore_bs(text.mask)
  text.tidy = gsub(pat.comment, '', text.mask)
  # inline comments should be termined by $ or \n
  text.tidy = gsub(paste(inline.comment, '(\n|$)', sep = ''), '  \\1\\2', text.tidy)
  # the rest of inline comments should be appended by \n
  gsub(inline.comment, '  \\1\n', text.tidy)
}


#' Format the R scripts under a directory
#'
#' This function first looks for all the R scripts under a directory (using the
#' pattern \code{"[.][RrSsQq]$"}), then uses \code{\link{tidy_source}} to tidy
#' these scripts. The original scripts will be overwritten with reformatted code
#' if reformatting was successful. You may need to back up the original
#' directory first if you do not fully understand the tricks
#' \code{\link{tidy_source}} is using.
#' @param path the directory
#' @param recursive whether to recursively look for R scripts under \code{path}
#' @param ... other arguments to be passed to \code{\link{tidy_source}}
#' @return Invisible \code{NULL}.
#' @author Yihui Xie <\url{http://yihui.name}>
#' @seealso \code{\link{tidy_source}}
#' @export
#' @examples
#' library(formatR)
#'
#' path = tempdir()
#' file.copy(system.file('demo', package = 'base'), path, recursive=TRUE)
#' tidy_dir(path, recursive=TRUE)
tidy_dir = function(path = '.', recursive = FALSE, ...) {
  flist = list.files(path, pattern = '[.][RrSsQq]$', full.names = TRUE, recursive = recursive)
  for (f in flist) {
    message('tidying ', f)
    try(tidy_source(f, file = f, ...))
  }
}
