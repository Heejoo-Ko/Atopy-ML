options(shiny.sanitize.errors = F)
source("global.R")
source("R/gee.R")
library(shiny)
library(shinycustomloader);library(survival);library(MatchIt);library(survey);library(ggplot2)
library(shinymanager);library(jskm);library(DT);library(jsmodule);library(forestplot);library(tsibble);library(prophet);library(feasts)
library(caret);library(randomForest);library(MLeval);library(MLmetrics)
nfactor.limit <- 21

#setwd("/home/js/ShinyApps/Sev-cardio/MS-registry/Tx_of_moderately_severeMS")

#credentials <- data.frame(
#  user = c("admin", "Sev-cardio"),
#  password = c("zarathuadmin", "Sev-cardio"),
#  admin = c(T, F),
#  stringsAsFactors = FALSE
#)

#create_db(credentials_data = credentials, sqlite_path = "database.sqlite")

conti_vars <- setdiff(names(out), factor_vars)
conti_vars <- setdiff(conti_vars,c("ID","date"))

predictiveValues <- function (data, lev = NULL, model = NULL){
  PPVobj <- posPredValue(data[, "pred"], data[, "obs"])
  NPVobj <- negPredValue(data[, "pred"], data[, "obs"])
  out <- c(PPVobj, NPVobj)
  names(out) <- c("PPV", "NPV")
  out}
MySummary  <- function(data, lev = NULL, model = NULL){
  a1 <- defaultSummary(data, lev, model)
  b1 <- twoClassSummary(data, lev, model)
  c1 <- prSummary(data, lev, model)
  d1 <- predictiveValues(data, lev, model)
  out <- c(a1,b1,c1,d1)
  out
}
get_best_result = function(caret_fit) {
  best = which(rownames(caret_fit$results) == rownames(caret_fit$bestTune))
  best_result = caret_fit$results[best, ]
  rownames(best_result) = NULL
  best_result
}
normalize <- function(x) {
  if(class(x)=="numeric"){
    return ((x-min(x)) / (max(x) - min(x)))
  } else{
    return (x)
  }
}

ui <- navbarPage("Atopy",
                 tabPanel("Table 1: Baseline", icon = icon("percentage"),
                          sidebarLayout(
                            sidebarPanel(
                              tb1moduleUI("tb1"),
                            ),
                            mainPanel(
                              withLoader(DTOutput("table1"), type="html", loader="loader6"),
                              wellPanel(
                                h5("Normal continuous variables  are summarized with Mean (SD) and t-test(2 groups) or ANOVA(> 2 groups)"),
                                h5("Non-normal continuous variables are summarized with median [IQR or min,max] and kruskal-wallis test"),
                                h5("Categorical variables  are summarized with table")
                              )
                            )
                          )
                          
                 ),
                 navbarMenu("Population estimation: GEE", icon = icon("list-alt"),
                            tabPanel("Linear",
                                     sidebarLayout(
                                       sidebarPanel(
                                         GEEModuleUI2("linear")
                                       ),
                                       mainPanel(
                                         withLoader(DTOutput("lineartable"), type="html", loader="loader6")
                                       )
                                     )
                            ),
                            tabPanel("Binomial",
                                     sidebarLayout(
                                       sidebarPanel(
                                         GEEModuleUI2("logistic")
                                       ),
                                       mainPanel(
                                         withLoader(DTOutput("logistictable"), type="html", loader="loader6")
                                       )
                                     )
                            )
                 ),
                 tabPanel("Individual prediction", 
                          sidebarLayout(
                            sidebarPanel(
                              selectInput("ID_pred", "ID",  unique(out$ID), unique(out$ID)[1]),
                              radioButtons("method_ml", "Model", c("LASSO", "Random forest"), "Random forest", inline = T),
                              selectInput("Dep_pred", "Dependent variable", varlist$Symptom, "sum_objective"),
                              selectInput("Indep_pred", "Independent variable", varlist[3:4], setdiff(vars.pred, c("season", "dow")), multiple = T),
                              actionButton("action_pred", "Run prediction")
                            ),
                            mainPanel(
                              withLoader(plotOutput("predplot", width = "100%"), type="html", loader="loader6"),
                              h3("Download options"),
                              wellPanel(
                                uiOutput("downloadControls_kap"),
                                downloadButton("downloadButton_kap", label = "Download the plot")
                              ),
                              tabsetPanel(type = "pills",
                                          tabPanel("Result",
                                                   verbatimTextOutput("res_ml")),
                                          tabPanel("Plot", 
                                                   radioButtons("plottype_ml", "Plot", c("ROC (train data)", "ROC (test data)", "VarImp"), "VarImp", inline = T),
                                                   withLoader(plotOutput("fig1"), type="html", loader="loader6"),
                                                   h3("Download options"),
                                                   wellPanel(
                                                     uiOutput("downloadControls_fig1"),
                                                     downloadButton("downloadButton_fig1", label = "Download the plot")
                                                   )),
                                          tabPanel("Table",
                                                   radioButtons("tabletype_ml","Table",c("Coeff","Metrics"),"Metrics",inline=T),
                                                   tableOutput("ml_table"))
                                          
                                          
                              )
                            )
                            
                          )
                          
                 )
                 
)



server <- function(input, output, session) {
  
  ## check_credentials returns a function to authenticate users
  
  observe({
    id <- input$ID_pred
    
    id_N <- out[ID==id,.N,]
    
    # NA 15% 미만인 변수만 독립변수에 포함
    tf<-data.frame(TF = t(out[ID==id,lapply(.SD, function(x){sum(is.na(x))/id_N < 0.15}), .SDcols = unlist(varlist[3:4])]))
    indep_pred_choices <- rownames(subset(tf,TF==TRUE))
    
    
    updateSelectInput(session, "Indep_pred",
                      choices = indep_pred_choices,
                      selected = setdiff(indep_pred_choices, c("season", "dow", "bath", "lotion"))
    )
  })
  
  
  out_tb1 <- callModule(tb1module2, "tb1", data = reactive(out[, .SD[1], keyby = "ID", .SDcols = varlist$Base]), data_label = reactive(out.label), data_varStruct = NULL, nfactor.limit = nfactor.limit, showAllLevels = F)
  
  output$table1 <- renderDT({
    tb <- out_tb1()$table
    cap <- out_tb1()$caption
    out.tb1 <- datatable(tb, rownames = T, extensions = "Buttons", caption = cap,
                         options = c(jstable::opt.tb1("tb1"),
                                     list(columnDefs = list(list(visible=FALSE, targets= which(colnames(tb) %in% c("test","sig"))))
                                     ),
                                     list(scrollX = TRUE)
                         )
    )
    if ("sig" %in% colnames(tb)){
      out.tb1 = out.tb1 %>% formatStyle("sig", target = 'row' ,backgroundColor = styleEqual("**", 'yellow'))
    }
    return(out.tb1)
  })
  
  
  out_linear <- callModule(GEEModuleLinear2, "linear", data = reactive(out), data_label = reactive(out.label), data_varStruct = reactive(varlist), nfactor.limit = nfactor.limit, id.gee = reactive("ID"))
  
  output$lineartable <- renderDT({
    hide = which(colnames(out_linear()$table) == "sig")
    datatable(out_linear()$table, rownames=T, extensions = "Buttons", caption = out_linear()$caption,
              options = c(jstable::opt.tbreg(out_linear()$caption),
                          list(columnDefs = list(list(visible=FALSE, targets =hide))
                          ),
                          list(scrollX = TRUE)
              )
    ) %>% formatStyle("sig", target = 'row',backgroundColor = styleEqual("**", 'yellow'))
  })
  
  out_logistic <- callModule(GEEModuleLogistic2, "logistic", data = reactive(out), data_label = reactive(out.label), data_varStruct = reactive(varlist), nfactor.limit = nfactor.limit, id.gee = reactive("ID"))
  
  output$logistictable <- renderDT({
    hide = which(colnames(out_logistic()$table) == "sig")
    datatable(out_logistic()$table, rownames=T, extensions = "Buttons", caption = out_logistic()$caption,
              options = c(jstable::opt.tbreg(out_logistic()$caption),
                          list(columnDefs = list(list(visible=FALSE, targets =hide))
                          ),
                          list(scrollX = TRUE)
              )
    ) %>% formatStyle("sig", target = 'row',backgroundColor = styleEqual("**", 'yellow'))
  })
  
  
  
  
  obj.ml <- eventReactive(input$action_pred, {
    withProgress(message = 'Run in progress',
                 detail = 'This may take a while...', value = 0, {
                   for (i in 1:100) {
                     incProgress(1/100)
                     Sys.sleep(0.01)
                   }
                   
                   
                   data <- out[ID==input$ID_pred, .SD, .SDcols = c("date", input$Indep_pred, input$Dep_pred)]
                   data$lag <- sapply(data$date, function(x){
                     dd <- as.character(data[date == (x-1)][[input$Dep_pred]])
                     return(ifelse(length(dd) == 0, NA, dd))})
                   
                   if(is.numeric(data[[input$Dep_pred]])){
                     data$lag <- as.numeric(data$lag)
                   }
                   
                   
                   
                   ###############
                   # data <- out[ID==49, .SD, .SDcols = c("date", "drug", "HCHO_in", "CO2_in", "temp_in", "sum_score")]
                   # data$lag <- sapply(data$date, function(x){
                   #   dd <- as.character(data[date == (x-1)][["sum_score"]])
                   #   return(ifelse(length(dd) == 0, NA, dd))})
                   # 
                   # if(is.numeric(data[["sum_score"]])){
                   #   data$lag <- as.numeric(data$lag)
                   # }
                   # ####
                   
                   
                   data <- na.omit(data)
                   
                   factor_now <- is.factor(data[[input$Dep_pred]])
                   
                   dep_mean <- 0
                   dep_sd <- 1
                   
                   if(input$method_ml=="LASSO"){
                     
                     factor_vars_now<-factor_vars
                     if(factor_now){
                       factor_vars_now<-c(factor_vars_now,"lag")
                     }
                     
                     if(!factor_now){
                       dep_mean <- mean(data[[input$Dep_pred]],na.rm=T)
                       dep_sd <- sd(data[[input$Dep_pred]],na.rm=T)  
                       # dep_mean <- mean(data[["sum_score"]],na.rm=T)
                       # dep_sd <- sd(data[["sum_score"]],na.rm=T)
                     }
                     
                     for (v in setdiff(names(data), factor_vars_now)){
                       data[[v]] <- (data[[v]] - mean(data[[v]], na.rm = T))/sd(data[[v]], na.rm = T)
                     }
                   }
                   
                   cut <- round(nrow(data)*0.7)
                   data.train <- data[1:(cut-1),]
                   data.test <- data[cut:nrow(data),]
                   
                   
                   # data.train <- DMwR::SMOTE(as.formula(paste(input$Dep_pred, "~ .")), data = data.train)
                   
                   
                   if(factor_now){
                     fitControl <- trainControl(method = "cv", number = 10,
                                                summaryFunction = MySummary, savePredictions=TRUE, classProbs=TRUE)  
                   }else{
                     fitControl <- trainControl(method = "cv", number = 10,
                                                summaryFunction = defaultSummary, savePredictions=TRUE, classProbs=FALSE)
                   }
                   
                   
                   method <- ifelse(input$method_ml == "LASSO", "glmnet", "rf")
                   tunegrid <- NULL
                   if (input$method_ml == "LASSO"){
                     tunegrid <- expand.grid(alpha = 1, lambda = 10^seq(-5, 3, length = 200))
                   }
                   rf1 <- train(as.formula(paste0(input$Dep_pred, " ~", paste(input$Indep_pred, collapse = "+"),"+ lag+ date")), data = data.train, method = method,
                                trControl = fitControl, tuneGrid = tunegrid)
                   
                   if(factor_now){
                     pred <- data.frame("Obs" = data[[input$Dep_pred]], "Pred" = predict(rf1, data, type = "prob")[, 2])
                     pred.train <- data.frame("Obs" = data.train[[input$Dep_pred]], "Pred" = predict(rf1, data.train, type = "prob")[, 2])
                     pred.test <- data.frame("Obs" = data.test[[input$Dep_pred]], "Pred" = predict(rf1, data.test, type = "prob")[, 2])
                   }else{
                     pred <- data.frame("Obs" = data[[input$Dep_pred]], "Pred" = predict(rf1, data))
                     pred.train <- data.frame("Obs" = data.train[[input$Dep_pred]], "Pred" = predict(rf1, data.train))
                     pred.test <- data.frame("Obs" = data.test[[input$Dep_pred]], "Pred" = predict(rf1, data.test))
                     if(input$method_ml == "LASSO"){
                       pred$Pred <- (pred$Pred * dep_sd) + dep_mean
                     }
                     
                   }
                   
                   
                   # #####
                   # method<-"rf"
                   # method<-"glmnet"
                   # rf1 <- train(as.formula(paste0("sum_score", " ~", "drug+HCHO_in+CO2_in+temp_in+lag+date")), data = data.train, method = method,
                   #              trControl = fitControl, tuneGrid = tunegrid)
                   # pred <- data.frame("Obs" = data[["sum_score"]], "Pred" = predict(rf1, newdata =  data))
                   # 
                   # #################
                   
                   
                   
                   if(factor_now){
                     my_ml_return<-list(obj = rf1, pred = pred, pred.train = pred.train, pred.test = pred.test, cmat.train = confusionMatrix(pred.train$Obs, predict(rf1, data.train)), cmat.test = confusionMatrix(pred.test$Obs, predict(rf1, data.test)))
                   }else{
                     my_ml_return<-list(obj = rf1, pred = pred, pred.train = pred.train, pred.test = pred.test, cmat.train = NULL, cmat.test = NULL)
                   }
                   
                   
                   return(my_ml_return)
                 })
    
  })
  
  obj.predplot <- reactive({
    
    data <- out[ID==input$ID_pred, .SD, .SDcols = c("date", input$Indep_pred, input$Dep_pred)]
    data$lag <- sapply(data$date, function(x){
      dd <- as.character(data[date == (x-1)][[input$Dep_pred]])
      return(ifelse(length(dd) == 0, NA, dd))})
    if(is.numeric(data[[input$Dep_pred]])){
      data$lag <- as.numeric(data$lag)
    }
    data <- na.omit(data)
    
    cut <- round(nrow(data)*0.7)
    data.train <- data[1:(cut-1),]
    data.test <- data[cut:nrow(data),]
    
    # yhat<-pred$Pred
    # res.ml<-data.table(dplyr::bind_cols(date = data$date, yhat = yhat, target = data[["sum_objective"]])) %>%
    #   melt(idvars = "ID", measure.vars = c("yhat", "target"))
    # ggpubr::ggline(res.ml, "date", "value", color = "variable", plot_type  = "l", xlab = "", ylab = "sum_objective") +
    #   geom_vline(xintercept=data.test[1,]$date, linetype='dotted') +
    #   scale_color_discrete(name = "Variable", labels = c("Predict", "sum_objective"))
    
    pred<-obj.ml()$pred
    
    factor_now <- is.factor(data[[input$Dep_pred]])
    if(factor_now){
      yhat <- as.factor(ifelse(pred$Pred >=0.5, "Yes", "No"))
    }else{
      yhat<-pred$Pred
    }
    
    res.ml<-data.table(dplyr::bind_cols(date = data$date, yhat = yhat, target = data[[input$Dep_pred]])) %>%
      melt(idvars = "ID", measure.vars = c("yhat", "target"))
    
    myplot<- ggpubr::ggline(res.ml, "date", "value", color = "variable", plot_type  = "l", xlab = "", ylab = input$Dep_pred) +
      geom_vline(xintercept=data.test[1,]$date, linetype='dotted') +
      scale_color_discrete(name = "Variable", labels = c("Predict", input$Dep_pred))
    
    return(myplot)
    
  })
  
  output$downloadControls_kap <- renderUI({
    fluidRow(
      column(4,
             selectizeInput("kap_file_ext", "File extension (dpi = 300)", 
                            choices = c("jpg","pdf", "tiff", "svg", "pptx"), multiple = F, 
                            selected = "pptx"
             )
      ),
      column(4,
             sliderInput("fig_width_kap", "Width (in):",
                         min = 5, max = 20, value = 10
             )
      ),
      column(4,
             sliderInput("fig_height_kap", "Height (in):",
                         min = 5, max = 20, value = 6
             )
      )
    )
  })
  
  output$predplot <- renderPlot({
    obj.predplot()
    
  })
  
  output$downloadButton_kap <- downloadHandler(
    filename =  function() {
      paste(input$ID_pred, "_", "Predict" , "_plot.", input$kap_file_ext ,sep="")
    },
    # content is a function with argument file. content writes the plot to the device
    content = function(file) {
      withProgress(message = 'Download in progress',
                   detail = 'This may take a while...', value = 0, {
                     for (i in 1:15) {
                       incProgress(1/15)
                       Sys.sleep(0.01)
                     }
                     
                     if (input$kap_file_ext == "pptx"){
                       my_vec_graph <- rvg::dml(ggobj  = obj.predplot())
                       doc <- officer::read_pptx()
                       doc <- officer::add_slide(doc, layout = "Title and Content", master = "Office Theme")
                       doc <- officer::ph_with(doc, my_vec_graph, location = officer::ph_location(width = input$fig_width_kap, height = input$fig_height_kap))
                       print(doc, target = file)
                       
                     } else{
                       ggsave(file, obj.km(), dpi = 300, units = "in", width = input$fig_width_kap, height =input$fig_height_kap)
                     }
                     
                   })
      
      
    })
  
  output$res_ml <- renderPrint({
    
    factor_now <- is.factor(out[[input$Dep_pred]])
    my_ml <- obj.ml()
    
    if(factor_now){
      my_ml_result<-list("Metrics" = my_ml$cmat, "Result" = my_ml$obj)
    }else{
      my_ml_result<-list("Result" = my_ml$obj)
    }
    
    return(my_ml_result)
  })
  
  obj.fig1 <- reactive({
    
    if (input$plottype_ml == "ROC (train data)"){
      
      factor_now <- is.factor(out[[input$Dep_pred]])
      
      if(factor_now){
        obj.roc <- pROC::roc(Obs ~ as.numeric(Pred), data = obj.ml()$pred.train)
        p <- pROC::ggroc(obj.roc) + see::theme_modern() + geom_abline(slope = 1, intercept = 1, lty = 2) +
          xlab("Specificity") + ylab("Sensitivity") + ggtitle(paste("AUC =", round(obj.roc$auc, 3)))
        return(p)  
      }else{
        return(NULL)
      }
      
    }else if(input$plottype_ml == "ROC (test data)"){
      
      factor_now <- is.factor(out[[input$Dep_pred]])
      
      if(factor_now){
        obj.roc <- pROC::roc(Obs ~ as.numeric(Pred), data = obj.ml()$pred.test)
        p <- pROC::ggroc(obj.roc) + see::theme_modern() + geom_abline(slope = 1, intercept = 1, lty = 2) +
          xlab("Specificity") + ylab("Sensitivity") + ggtitle(paste("AUC =", round(obj.roc$auc, 3)))
        return(p)  
      }else{
        return(NULL)
      }
      
    }else{
      ggplot(varImp(obj.ml()$obj, scale = F), width = 0.05) + ggpubr::theme_classic2()
      #plot(varImp(obj.ml()$obj, scale = F))
    }
  })
  
  output$ml_table <- renderTable({
    if(input$tabletype_ml=="Metrics"){
      
      factor_now <- is.factor(out[[input$Dep_pred]])
      
      if(factor_now){
        
        Matt_Coef <- function (conf_matrix)
        {
          TP <- conf_matrix$table[1,1]
          TN <- conf_matrix$table[2,2]
          FP <- conf_matrix$table[1,2]
          FN <- conf_matrix$table[2,1]
          
          mcc_num <- (TP*TN - FP*FN)
          mcc_den <- 
            as.double((TP+FP))*as.double((TP+FN))*as.double((TN+FP))*as.double((TN+FN))
          
          mcc_final <- mcc_num/sqrt(mcc_den)
          return(mcc_final)
        }
        
        cm<-obj.ml()$cmat.train
        cmtable.train<-data.frame(cbind(t(cm$overall),t(cm$byClass)))[,c("Sensitivity","Specificity","Accuracy","Precision","Pos.Pred.Value","Neg.Pred.Value")]
        MCCresult<-data.frame(Matt_Coef(cm))
        colnames(MCCresult)<-"MCC"
        cmtable.train<-data.frame(cmtable.train,MCCresult)
        
        cm<-obj.ml()$cmat.test
        cmtable.test<-data.frame(cbind(t(cm$overall),t(cm$byClass)))[,c("Sensitivity","Specificity","Accuracy","Precision","Pos.Pred.Value","Neg.Pred.Value")]
        MCCresult<-data.frame(Matt_Coef(cm))
        colnames(MCCresult)<-"MCC"
        cmtable.test<-data.frame(cmtable.test,MCCresult)
        
        cmtable <- rbind(cmtable.train, cmtable.test)
        rownames(cmtable) <- c("Train","Test")
        
        
      }else{
        
        cmtable.train<-data.frame(RMSE = RMSE(obj.ml()$pred.train$Obs,obj.ml()$pred.train$Pred))
        cmtable.test<-data.frame(RMSE = RMSE(obj.ml()$pred.test$Obs,obj.ml()$pred.test$Pred))
        
        cmtable <- rbind(cmtable.train, cmtable.test)
        rownames(cmtable) <- c("Train","Test")
        
      }
      
      return(cmtable)
      
      
    } else{
      if(input$method_ml=="LASSO"){
        lc<-coef(obj.ml()$obj$finalModel, obj.ml()$obj$bestTune$lambda)[-1,]
        df<-data.frame(Coefficient = lc)
      } else{
        
        lc<-data.frame(varImp(obj.ml()$obj$finalModel, scale = F))
        colnames(lc)<-NULL
        df<-data.frame(Importance = lc)
      }
      
      return(df)
    }
    
  },
  rownames = TRUE
  )
  
  output$fig1 <- renderPlot({
    validate(
      need(try(is.factor(out[[input$Dep_pred]]) | input$plottype_ml == "VarImp"), "only for categorical variable")
    )
    
    obj.fig1()
  })
  
  
  output$downloadControls_fig1 <- renderUI({
    fluidRow(
      column(4,
             selectizeInput("fig1_file_ext", "File extension (dpi = 300)", 
                            choices = c("jpg","pdf", "tiff", "svg", "pptx"), multiple = F, 
                            selected = "pptx"
             )
      ),
      column(4,
             sliderInput("fig_width_fig1", "Width (in):",
                         min = 5, max = 20, value = 8
             )
      ),
      column(4,
             sliderInput("fig_height_fig1", "Height (in):",
                         min = 5, max = 20, value = 6
             )
      )
    )
  })
  
  output$downloadButton_fig1 <- downloadHandler(
    filename =  function() {
      paste("fig1.", input$fig1_file_ext ,sep="")
    },
    # content is a function with argument file. content writes the plot to the device
    content = function(file) {
      withProgress(message = 'Download in progress',
                   detail = 'This may take a while...', value = 0, {
                     for (i in 1:15) {
                       incProgress(1/15)
                       Sys.sleep(0.01)
                     }
                     
                     if (input$fig1_file_ext == "pptx"){
                       my_vec_graph <- rvg::dml(ggobj  = obj.fig1())
                       
                       doc <- officer::read_pptx()
                       doc <- officer::add_slide(doc, layout = "Title and Content", master = "Office Theme")
                       doc <- officer::ph_with(doc, my_vec_graph, location = officer::ph_location(width = input$fig_width_fig1, height = input$fig_height_fig1))
                       print(doc, target = file)
                       
                     } else{
                       ggsave(file, obj.fig1(), dpi = 300, units = "in", width = input$fig_width_fig1, height =input$fig_height_fig1)
                     }
                     
                   })
      
    })
  
  
  session$onSessionEnded(function() {
    session$close()
  })
  
}

shinyApp(ui, server)