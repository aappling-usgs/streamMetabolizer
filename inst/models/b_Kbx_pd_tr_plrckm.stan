// b_Kbx_pd_tr_plrckm.stan

data {
  // Parameters of priors on metabolism
  real GPP_daily_mu;
  real GPP_daily_lower;
  real<lower=0> GPP_daily_sigma;
  real ER_daily_mu;
  real ER_daily_upper;
  real<lower=0> ER_daily_sigma;
  
  // Parameters of hierarchical priors on K600_daily (binned_sdfixed model)
  int <lower=1> b; // number of K600_lnQ_nodes
  real K600_lnQ_nodediffs_sdlog;
  vector[b] K600_lnQ_nodes_meanlog;
  vector[b] K600_lnQ_nodes_sdlog;
  real<lower=0> K600_daily_sigma;
  
  // Error distributions
  real<lower=0> err_proc_dayiid_sdlog_sigma;
  
  // Data dimensions
  int<lower=1> d; // number of dates
  real<lower=0> timestep; // length of each timestep in days
  int<lower=1> n24; // number of observations in first 24 hours per date
  int<lower=1> n; // number of observations per date
  
  // Daily data
  vector[d] DO_obs_1;
  int<lower=1,upper=b> lnQ_bins[2,d];
  vector<lower=0,upper=1>[d] lnQ_bin_weights[2];
  
  // Data
  vector[d] DO_obs[n];
  vector[d] DO_sat[n];
  vector[d] frac_GPP[n];
  vector[d] frac_ER[n];
  vector[d] frac_D[n];
  vector[d] depth[n];
  vector[d] KO2_conv[n];
}

parameters {
  vector<lower=GPP_daily_lower>[d] GPP_daily;
  vector<upper=ER_daily_upper>[d] ER_daily;
  vector<lower=0>[d] K600_daily;
  
  vector[b] lnK600_lnQ_nodes;
  
  real<lower=0> err_proc_dayiid_sdlog_scaled;
  vector<lower=0>[d] mult_GPP[n];
}

transformed parameters {
  vector[d] K600_daily_predlog;
  real<lower=0> err_proc_dayiid_sdlog;
  vector[d] GPP_inst[n];
  vector[d] ER_inst[n];
  vector[d] KO2_inst[n];
  vector[d] DO_mod[n];
  vector[d] err_proc_dayiid[n];
  
  // Rescale error distribution parameters
  err_proc_dayiid_sdlog = err_proc_dayiid_sdlog_sigma * err_proc_dayiid_sdlog_scaled;
  
  // Hierarchical, binned_sdfixed model of K600_daily
  K600_daily_predlog = lnK600_lnQ_nodes[lnQ_bins[1]] .* lnQ_bin_weights[1] + 
                       lnK600_lnQ_nodes[lnQ_bins[2]] .* lnQ_bin_weights[2];
  
  // Model DO time series
  // * trapezoid version
  // * no observation error
  // * no process error
  // * reaeration depends on DO_mod
  
  // Calculate individual process rates
  for(i in 1:n) {
    GPP_inst[i] = GPP_daily .* frac_GPP[i];
    err_proc_dayiid[i] = GPP_inst[i] .* (mult_GPP[i] - 1);
    ER_inst[i] = ER_daily .* frac_ER[i];
    KO2_inst[i] = K600_daily .* KO2_conv[i];
  }
  
  // DO model
  for(i in 1:(n-1)) {
    DO_mod[i+1] =
      DO_mod_partial[i] .*
        (2.0 - KO2_inst[i] * timestep) ./ (2.0 + KO2_inst[i+1] * timestep) + (
        (GPP_inst[i] + ER_inst[i] + err_proc_dayiid[i]) ./ depth[i] +
        (GPP_inst[i+1] + ER_inst[i+1] + err_proc_dayiid[i+1]) ./ depth[i+1] +
        KO2_inst[i] .* DO_sat[i] + KO2_inst[i+1] .* DO_sat[i+1]
      ) .* (timestep ./ (2.0 + KO2_inst[i+1] * timestep));
  }
}

model {
  // Daytime-only independent, identically distributed process error
  for(i in 1:n) {
    mult_GPP[i] ~ lognormal(0, err_proc_dayiid_sdlog);
  }
  // SD (sigma) of the daytime IID process errors
  err_proc_dayiid_sdlog_scaled ~ normal(0, 1);
  
  // Daily metabolism priors
  GPP_daily ~ normal(GPP_daily_mu, GPP_daily_sigma);
  ER_daily ~ normal(ER_daily_mu, ER_daily_sigma);
  K600_daily ~ normal(exp(K600_daily_predlog), K600_daily_sigma);
  // Hierarchical constraints on K600_daily (binned_sdfixed model)
  lnK600_lnQ_nodes ~ normal(K600_lnQ_nodes_meanlog, K600_lnQ_nodes_sdlog);
  for(k in 2:b) {
    lnK600_lnQ_nodes[k] ~ normal(lnK600_lnQ_nodes[k-1], K600_lnQ_nodediffs_sdlog);
  }
  
}
generated quantities {
  vector[d] GPP;
  vector[d] ER;
  
  for(j in 1:d) {
    GPP[j] = sum(GPP_inst[1:n24,j]) / n24;
    ER[j] = sum(ER_inst[1:n24,j]) / n24;
  }
  
}
