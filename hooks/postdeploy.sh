DATETIME=$(date '+%Y%m%d%H%M%S')
az acr build -r $ACR_NAME -t chat-app:$DATETIME src

az containerapp update -n chat-app -g $RESOURCE_GROUP_NAME --image "$ACR_NAME.azurecr.io/chat-app:$DATETIME"
az containerapp job update -n indexer-job -g $RESOURCE_GROUP_NAME --image "$ACR_NAME.azurecr.io/chat-app:$DATETIME"