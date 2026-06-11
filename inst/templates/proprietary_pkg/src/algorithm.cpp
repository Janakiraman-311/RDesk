// {{PKG_NAME}} — Proprietary Algorithm
// Created: {{DATE}}
//
// IMPORTANT: This file contains proprietary source code.
// It is compiled to a binary .dll/.so during build_app()
// and is NEVER distributed to end users.
//
// Write your algorithms here using standard Rcpp syntax.
// Run Rcpp::compileAttributes() after any changes.

#include <Rcpp.h>
using namespace Rcpp;

// ── Licence validation ────────────────────────────────────────────────
// Remove or replace with your own licence validation logic
static bool check_licence() {
  const char* key = std::getenv("{{PKG_NAME}}_LICENCE_KEY");
  if (!key || std::string(key).empty()) {
    return false;
  }
  // Add your licence validation logic here
  // For example: validate a signed token, check hostname, etc.
  return true;
}

// ── Example algorithm — replace with your implementation ──────────────

//' Example computation (replace with your algorithm)
//'
//' @param x A numeric vector of input values
//' @param multiplier A scalar multiplier
//' @return A numeric vector of results
//' @export
// [[Rcpp::export]]
NumericVector {{ALGORITHM_NAME}}(NumericVector x, double multiplier = 1.0) {
  // Licence check — runs in compiled binary, cannot be bypassed from R
  if (!check_licence()) {
    Rcpp::stop(
      "{{PKG_NAME}}: Licence key not found. "
      "Set environment variable {{PKG_NAME}}_LICENCE_KEY. "
      "Contact support for a licence key."
    );
  }

  // Your proprietary algorithm here
  // This code is compiled to machine code — client cannot read it
  int n = x.size();
  NumericVector result(n);

  for (int i = 0; i < n; i++) {
    result[i] = x[i] * multiplier;
  }

  return result;
}


//' Validate input data structure
//'
//' @param df A data frame to validate
//' @param required_cols Character vector of required column names
//' @return TRUE if valid, stops with error if invalid
//' @export
// [[Rcpp::export]]
bool validate_structure(DataFrame df, CharacterVector required_cols) {
  CharacterVector cols = df.names();

  for (int i = 0; i < required_cols.size(); i++) {
    bool found = false;
    for (int j = 0; j < cols.size(); j++) {
      if (required_cols[i] == cols[j]) {
        found = true;
        break;
      }
    }
    if (!found) {
      Rcpp::stop(
        "Required column '%s' not found in data frame.",
        Rcpp::as<std::string>(required_cols[i]).c_str()
      );
    }
  }
  return true;
}
