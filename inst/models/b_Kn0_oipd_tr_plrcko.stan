// b_Kn0_oipd_tr_plrcko.stan

data {
  // Parameters of priors on metabolism
  real GPP_daily_mu;
  real GPP_daily_lower;
  real<lower=0> GPP_daily_sigma;
  real ER_daily_mu;
  real ER_daily_upper;
  real<lower=0> ER_daily_sigma;
  
  // Parameters of hierarchical priors on K600_daily (normal_sdzero model)
  real K600_daily_meanlog_meanlog;
  real<lower=0> K600_daily_meanlog_sdlog;
  
  // Error distributions
  real<lower=0> err_obs_iid_sigma_scale;
  real<lower=0> err_proc_dayiid_sdlog_sigma;
  
  // Data dimensions
  int<lower=1> d; // number of dates
  real<lower=0> timestep; // length of each timestep in days
  int<lower=1> n24; // number of observations in first 24 hours per date
  int<lower=1> n; // number of observations per date
  
  // Daily data
  vector[d] DO_obs_1;
  
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
  
  real K600_daily_predlog;
  
  real<lower=0> err_obs_iid_sigma_scaled;
  real<lower=0> err_proc_dayiid_sdlog_scaled;
  vector<lower=0>[d] mult_GPP[n];
}

transformed parameters {
  vector[d] K600_daily;
  real<lower=0> err_obs_iid_sigma;
  real<lower=0> err_proc_dayiid_sdlog;
  vector[d] GPP_inst[n];
  vector[d] ER_inst[n];
  vector[d] KO2_inst[n];
  vector[d] DO_mod[n];
  vector[d] err_proc_dayiid[n];
  
  // Rescale error distribution parameters
  err_obs_iid_sigma = err_obs_iid_sigma_scale * err_obs_iid_sigma_scaled;
  err_proc_dayiid_sdlog = err_proc_dayiid_sdlog_sigma * err_proc_dayiid_sdlog_scaled;
  
  // Hierarchical, normal_sdzero model of K600_daily
  for(j in 1:d) {
    K600_daily[j] = exp(K600_daily_predlog);
  }
  
  // Model DO time series
  // * trapezoid version
  // * observation error
  // * no process error
  // * reaeration depends on DO_obs
  
  // Calculate individual process rates
  for(i in 1:n) {
    GPP_inst[i] = GPP_daily .* frac_GPP[i];
    err_proc_dayiid[i] = GPP_inst[i] .* (mult_GPP[i] - 1);
    ER_inst[i] = ER_daily .* frac_ER[i];
    KO2_inst[i] = K600_daily .* KO2_conv[i];
  }
  
  // DO model
  DO_mod[1] = DO_obs_1;
  for(i in 1:(n-1)) {
    DO_mod[i+1] =
      DO_mod[i] + (
        - KO2_inst[i] .* DO_obs[i] - KO2_inst[i+1] .* DO_obs[i+1] +
        (GPP_inst[i] + ER_inst[i] + err_proc_dayiid[i]) ./ depth[i] +
        (GPP_inst[i+1] + ER_inst[i+1] + err_proc_dayiid[i+1]) ./ depth[i+1] +
        KO2_inst[i] .* DO_sat[i] + KO2_inst[i+1] .* DO_sat[i+1]
      ) * (timestep / 2.0);
  }
}

model {
  // Daytime-only independent, identically distributed process error
  for(i in 1:n) {
    mult_GPP[i] ~ lognormal(0, err_proc_dayiid_sdlog);
  }
  // SD (sigma) of the daytime IID process errors
  err_proc_dayiid_sdlog_scaled ~ normal(0, 1);
  
  // Independent, identically distributed observation error
  for(i in 2:n) {
    DO_obs[i] ~ normal(DO_mod[i], err_obs_iid_sigma);
  }
  // SD (sigma) of the observation errors
  err_obs_iid_sigma_scaled ~ cauchy(0, 1);
  
  // Daily metabolism priors
  GPP_daily ~ normal(GPP_daily_mu, GPP_daily_sigma);
  ER_daily ~ normal(ER_daily_mu, ER_daily_sigma);
  // Hierarchical constraints on K600_daily (normal_sdzero model)
  K600_daily_predlog ~ normal(K600_daily_meanlog_meanlog, K600_daily_meanlog_sdlog);
  
}
generated quantities {
  vector[d] err_obs_iid[n];
  vector[d] GPP;
  vector[d] ER;
  
  for(i in 1:n) {
    err_obs_iid[i] = DO_mod[i] - DO_obs[i];
  }
  for(j in 1:d) {
    GPP[j] = sum(GPP_inst[1:n24,j]) / n24;
    ER[j] = sum(ER_inst[1:n24,j]) / n24;
  }
  
}
