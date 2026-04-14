#!/bin/bash

services=(
  adservice
  cartservice
  checkoutservice
  currencyservice
  emailservice
  loadgenerator
  paymentservice
  productcatalogservice
  recommendationservice
  shippingservice
)
for i in "${services[@]}"; do
  cd "$i"
  touch deployment.yaml
  touch service.yaml
  touch serviceAccount.yaml
  cd ..
done 