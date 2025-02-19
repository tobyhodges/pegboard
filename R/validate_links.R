#' Validate Links in a markdown document
#'
#' This function will validate that links do not throw an error in markdown
#' documents. This will include links to images and will respect robots.txt for
#' websites.
#'
#' @details
#'
#' ## Link Validity
#'
#' All links must resolve to a specific location. If it does not exist, then the
#' link is invalid. At the moment, we can only do local links. 
#'
#' ### External links
#'
#' These links must start with a valid and secure protocol. Allowed protocols
#' are taken from the [allowed protocols in Wordpress](https://developer.wordpress.org/reference/functions/wp_allowed_protocols/#return):
#'
#' ```{r, echo = FALSE, comment = NA, results = 'asis'}
#' prots <- toString(asNamespace('pegboard')$allowed_uri_protocols[-1])
#' writeLines(strwrap(prots, width = 60))
#' ```
#'
#' Misspellings and unsupported protocols (e.g. `javascript:` and `bitcoin:`
#' will be flagged).
#'
#' In addition, we will enforce the use of HTTPS over HTTP.
#'
#' ### Cross-lesson links
#'
#' These links will have no protocol, but should resolve to the HTML version of
#' a page and have the correct capitalisation.
#'
#' ### Anchors (aka fragments)
#'
#' Anchors are located at the end of URLs that start with a `#` sign. These are
#' used to indicate a section of the documenation or a span id.
#'
#' ## Accessibility (a11y)
#' 
#' Accessibillity ensures that your links are accurate and descriptive for 
#' people who have slow connections or use screen reader technology. 
#'
#' ### Alt-text (for images)
#'
#' All images must have associated alt-text. In pandoc, this is acheived by
#' writing the `alt` attribute in curly braces after the image: 
#' `![image caption](link){alt='alt text'}`:
#' <https://webaim.org/techniques/alttext/>
#'
#' ### Descriptive text
#'
#' All links must have descriptive text associated with them, which is 
#' beneficial for screen readers scanning the links on a page to not have a
#' list full of "link", "link", "link":
#' <https://webaim.org/techniques/hypertext/link_text#uninformative>
#'
#' ### Text length
#'
#' Link text length must be greater than 1: 
#' <https://webaim.org/techniques/hypertext/link_text#link_length>
#'
#' @note At the moment, we do not currently test if all links are reachable.
#'   This is a feature planned for the future.
#'
#'   This function is internal. Please use the methods for the [Episode] and
#'   [Lesson] classes.
#'
#' @param yrn a [tinkr::yarn] or [Episode] object.
#' @return a data frame with parsed information from [xml2::url_parse()] and
#'   columns of logical values indicating the tests that passed.
#' @keywords internal
#' @rdname validate_links
#' @seealso [Episode] and [Lesson] for the methods that will throw warnings
#' @examples
#' l <- Lesson$new(lesson_fragment())
#' e <- l$episodes[[3]]
#' # Our link validators run a series of tests on links and images and return a 
#' # data frame with information about the links (via xml2::url_parse), along 
#' # with the results of the tests
#' v <- asNamespace('pegboard')$validate_links(e)
#' names(v)
#' v
#' # URL protocols -----------------------------------------------------------
#' # To avoid potentially malicious situations, we have an explicit list of
#' # allwed URI protocols, which can be found in the `allowed_uri_protocols`
#' # character vector:
#' asNamespace('pegboard')$allowed_uri_protocols
#' # note that we make an additional check for the http protocol.
#' 
#' # Creating Warnings from the table ----------------------------------------
#' # The validator does not produce any warnings or messages, but this data
#' # frame can be passed on to other functions that will throw them for us. We
#' # have a function that will throw a warning/message for each link that
#' # fails the tests. These messages are controlled by `link_tests` and 
#' # `link_info`.
#' asNamespace('pegboard')$link_tests
#' asNamespace('pegboard')$link_info
#' asNamespace('pegboard')$throw_link_warnings(v)
validate_links <- function(yrn) {
  VAL <- make_link_table(yrn)
  if (length(VAL) == 0L || is.null(VAL)) {
    return(invisible(NULL))
  }
  VAL[names(link_tests)] <- TRUE
  source_list <- link_source_list(VAL)
  VAL <- link_known_protocol(VAL)
  VAL <- link_enforce_https(VAL)
  VAL <- link_internal_anchor(VAL, source_list, yrn$headings, yrn$body)
  VAL <- link_internal_file(VAL, source_list, fs::path_dir(yrn$path))
  VAL <- link_internal_well_formed(VAL, source_list)
  VAL <- link_all_reachable(VAL)
  VAL <- link_img_alt_text(VAL)
  VAL <- link_descriptive(VAL)
  VAL <- link_length(VAL)
  VAL
}

#' @rdname validate_links
#' @format - `allowed_uri_protocols` a character string of length `r length(allowed_uri_protocols)`
allowed_uri_protocols <- c(
  # We are defining an allow list here because a forbidden list is ever shifting
  # see: <https://security.stackexchange.com/a/148464/170657>
  # NOTE: we include HTTP here, but we invalidate it later
  '', 'http', 'https', 'ftp', 'ftps', 'mailto', 'news', 'irc', 'irc6', 'ircs',
  'gopher', 'nntp', 'feed', 'telnet', 'mms', 'rtsp', 'sms', 'svn', 'tel', 'fax',
  'xmpp', 'webcal', 'urn'
)

#' @rdname validate_links
link_known_protocol <- function(VAL) {
  VAL$known_protocol <- VAL$scheme %in% allowed_uri_protocols
  VAL
}

#' @rdname validate_links
link_enforce_https <- function(VAL) {
  # valid if we have a known scheme and it does not use http
  known_protocol <- VAL$known_protocol %||% (VAL$scheme %in% allowed_uri_protocols)
  VAL$enforce_https <- known_protocol & VAL$scheme != "http"
  VAL
}


#' @rdname validate_links
link_all_reachable <- function(VAL) {
  # TODO: implement a link checker for external links This is unfortunately
  # difficult and time-consuming due to robots.txt and other protocols/issues.
  # Maybe httr2 might be able to help solve this
  VAL
}

#' @rdname validate_links
link_img_alt_text <- function(VAL) {
  img <- VAL$type %in% c("image", "img")
  okay <- !is.na(VAL$alt) # alt="" is actually an OKAY solution, indicating a decorative image
  VAL$img_alt_text[img] <- okay[img]
  VAL
}

#' @rdname validate_links
link_length <- function(VAL) {
  is_link <- VAL$type == "link" & !VAL$anchor
  VAL$link_length[is_link] <- !grepl("^.?$", trimws(VAL$text[is_link]))
  VAL
}

#' @rdname validate_links
link_descriptive <- function(VAL) {
  more <- paste0("(for )?", c("more", "more info(rmation)?"))
  uninformative <- paste0(
    "^([[:punct:]]*(",
    paste(
      c("link", "this", "this link", "a link", "link to",
        paste0(c("here", "click here", "over here"), "( for)?"),
        paste0(c(more, "read more", "read on"), "( about)?")
      ),
      collapse = ")|("
    ), 
    ")[[:punct:]]*)$"
  )
  bad <- grepl(uninformative, trimws(VAL$text), ignore.case = TRUE, perl = TRUE)
  body_links <- !VAL$anchor
  VAL$descriptive[body_links] <- !bad[body_links]
  VAL
}

#' @rdname validate_links
#' @param lt the output of [make_link_table()]
link_source_list <- function(lt) {
  # Create a list of logical vectors from a link table. These vectors indicate
  # the source of a given link.
  internal <- lt$server == "" & lt$scheme == "" & is.na(lt$port) & lt$user == ""
  list(
    external   = !internal,
    internal   = internal,
    in_page    = internal & lt$path == "" & lt$fragment != "",
    cross_page = internal & lt$path != "",
    is_anchor  = purrr::map_lgl(lt$path %in% lt$rel, identical, TRUE),
    NULL
  )
}

#' @rdname validate_links
#' @param source_list output of `link_source_list`
#' @param headings an `xml_nodeset` of headings
#' @param body an `xml_document`
link_internal_anchor <- function(VAL, source_list, headings, body) {
  in_page <- source_list$in_page
  if (any(in_page)) {
    headings <- xml2::xml_text(headings)
    headings <- clean_headings(headings)
    spans    <- fetch_anchor_span_ids(body)
    anchors  <- c(headings, spans)
    VAL$internal_anchor[in_page] <- VAL$fragment[in_page] %in% anchors
  }
  VAL
}

#' @rdname validate_links
#' @param root the root path to the lesson that contains this file.
link_internal_file <- function(VAL, source_list, root) {
  to_check <- source_list$cross_page & !source_list$is_anchor
  if (any(to_check)) {
    VAL$internal_file[to_check] <- test_file_existence(VAL$path[to_check], root)
  }
  VAL
}

#' @rdname validate_links
link_internal_well_formed <- function(VAL, source_list) {
  to_flag <- source_list$cross_page & source_list$is_anchor
  VAL$internal_well_formed[to_flag] <- FALSE 
  VAL
}


#' @rdname validate_links
#' @export
#' @format - `link_tests` a character string of length `r length(link_tests)`
#'   containing templates that use the output of `validate_links()` for 
#'   formatting.
link_tests <- c(
  known_protocol  = "[invalid protocol]: {scheme}",
  enforce_https = "[needs HTTPS]: [{text}]({orig})",
  internal_anchor = "[missing anchor]: [{text}]({orig})",
  internal_file = "[missing file]: [{text}]({orig})",
  internal_well_formed = "[incorrect formatting]: [{text}][{orig}] -> [{text}]({orig})",
  all_reachable = "",
  img_alt_text  = "[image missing alt-text]: {orig}",
  descriptive   = "[uninformative link text]: [{text}]({orig})",
  link_length   = "[link text too short]: [{text}]({orig})",
  NULL
)

#' @rdname validate_links
#' @format - `link_info` a character string of length `r length(link_info)`
#'   that gives information and informative links for additional context for
#'   failures.
link_info <- c(
  known_protocol  = "Links must have a known URL protocol (e.g. https, ftp, mailto). See <https://developer.wordpress.org/reference/functions/wp_allowed_protocols/#return> for a list of acceptable protocols.",
  enforce_https = "Links must use HTTPS <https://https.cio.gov/everything/>",
  internal_anchor = "Some link anchors for relative links (e.g. [anchor]: link) are missing",
  internal_file = "Some linked internal files do not exist",
  internal_well_formed = "Some links were incorrectly formatted",
  all_reachable = "",
  img_alt_text  = "Images need alt-text <https://webaim.org/techniques/hypertext/link_text#alt_link>",
  descriptive   = "Avoid uninformative link phrases <https://webaim.org/techniques/hypertext/link_text#uninformative>",
  link_length   = "Avoid single-letter or missing link text <https://webaim.org/techniques/hypertext/link_text#link_length>",
  NULL
)


validate_known_rot <- function(lt, path, verbose = TRUE, cli = TRUE) {
  # There are some links that are notorious for link rot. In these cases, we 
  # should absolutely invalidate them.
  rotten <- c(
    # NOTE: Add new rotten URLs with their solutions here
    "exts.ggplot2.tidyverse.org/" = "(www.)?ggplot2-exts.org",
    NULL
  )
  res <- !any(matched <- vapply(rotten, grepl, logical(nrow(lt)), lt$server))
  if (verbose && !res) {
    bad_links <- lt$server[rowSums(res) > 0L]
  }
}

# TODO: adjust expectations based on what we want to do with the links.
# We have a situation here where we want to know: Which links represent the
# truth?
#
# 1. Links relative to the top-level directory?
# 2. Links relative to everything in site/built (markdown output)?
# 3. Links relative to site/docs (HTML output)?
#
# At the moment, we are validating for (1) and I think that's where we want to
# stay because that's the one that will allow for the most portability since 
# you can predict how to transfer the files to new structures. 
#
# TODO: add Episode$sandpaper to be `TRUE` if the _initial_ state was a
#   sandpaper lesson and `FALSE` otherwise, so we know what to expect.
test_file_existence <- function(paths, home) {
  # Add home path, assuming that we can link out from the episode and it will
  # link back to something real
  exists_here <- exists_at_all(fs::path_norm(fs::path(home, paths)))
  # The folders that we can possibly inspect
  maybe <- c(# sandpaper folders
    ".", "episodes", "learners", "instructors", "profiles", 
    # styles folders
    "_episodes", "_episodes_rmd", "_extras", "_includes"
  )
  # Eliminate folders that don't actually exist
  probably <- maybe[fs::file_exists(fs::path(home, "..", maybe))]
  # Check in those folders for these files
  exists_folders <- purrr::transpose(purrr::map(probably, exists_in_folder, paths, home))
  exists_folders <- purrr::map(exists_folders, purrr::flatten_lgl)
  # Return if any of them exist
  exists_here | purrr::map_lgl(exists_folders, any, na.rm = TRUE)

}

exists_at_all <- function(call_me_maybe) {
  # Catch the folders and the images
  exists_organic <- fs::file_exists(call_me_maybe)
  # Catch markdown files to be translated to HTML
  exists_md      <- fs::file_exists(fs::path_ext_set(call_me_maybe, "md"))
  # Catch R Markdown files to be translated to HTML
  exists_rmd     <- fs::file_exists(fs::path_ext_set(call_me_maybe, "Rmd"))
  # Return the winners
  exists_organic | exists_md | exists_rmd

}

exists_in_folder <- function(folder = "_extras", paths, home) {
  # Adding a backtrack to a higher folder
  the_paths <- fs::path_norm(fs::path(home, "..", folder, paths))
  res <- exists_at_all(the_paths)
  names(res) <- seq(paths)
  res
}

# transform the headings to their expected anchors
clean_headings <- function(headings) {
  anchor_regex <- ".*[[:space:]][{].*(<?#)([^[:space:]]+).*[}]"
  anchor_swapped <- gsub(anchor_regex, "\\2", headings, perl = TRUE)
  no_curlies     <- gsub("([{].+?[}]) ?$", "", anchor_swapped)
  emoji_eliminated <- gsub("(<?:)[_a-z0-9]+(?=:) ?", "", 
    no_curlies, perl = TRUE)
  lower_dash <- gsub("[[:punct:][:space:]]+", "-", tolower(emoji_eliminated))
  trim_dash <- gsub("[-]$", "", gsub("^[-]", "", lower_dash))
  gsub("\\.", "-", make.unique(trim_dash))
}

fetch_anchor_span_ids <- function(body, ns = tinkr::md_ns()) {
  spans <- find_anchor_spans(body, ns)
  clean_headings(paste("h1", sub("[}].*$", "}", xml2::xml_text(spans))))
}

find_anchor_spans <- function(body, ns = tinkr::md_ns()) {
  asis_node <- "md:text[@asis][text()=']']"
  curly     <- "following-sibling::md:text[1][starts-with(text(), '{#')]"
  xml2::xml_find_all(body, sprintf(".//%s/%s", asis_node, curly), ns = ns)
}
