#require(lattice)
args=(commandArgs(TRUE))

#all proteins;  length is 3d column
fileName_all<-args[[1]]
#annotated proteins
fileName_ann<-args[[2]]
#not annotated proteins
fileName_nAnn<-args[[3]]
#output file name
outFile <-args[[4]]
specie<-args[[5]]

#print(outFile);

data1<-read.table(fileName_all)

sizeAnnot<-file.info(fileName_ann)$size
if(sizeAnnot>0){	
 data1_ann<-read.table(fileName_ann) 
}else{
 data1_ann<-NA 
}

sizeNotAnnot<-file.info(fileName_nAnn)$size
if(sizeNotAnnot > 0){
 data1_nAnn<-read.table(fileName_nAnn)
}else{
 data1_nAnn<-NA 
}

#all
data<-subset(data1,V3<1000)
ld<-nrow(subset(data1,V3>=1000))
d<-density(data[,3])
x<-data[,3]
h<-hist(data[,3], breaks=seq(0,1000, by=10),plot="FALSE")

png(filename=outFile, height=640, width=480,bg="white")

plot(h,main=paste("Protein length distribution,\n",specie),col="blue",xlab="Length (AAs)", cex.axis=2, cex.lab=2)
lines(x = d$x, y = d$y * length(x) * diff(h$breaks)[1], lwd = 2,col="blue")

#annotated
if(!is.na(data1_ann)){
 data_ann<-subset(data1_ann,V3<1000)
 ldAn<-nrow(subset(data1_ann,V3>=1000))
 dann<-density(data_ann[,3])
 xann<-data_ann[,3]
 hann<-hist(data_ann[,3], breaks=seq(0,1000, by=10),plot="FALSE")
 plot(hann, col="red",add=T)
 lines(x = dann$x, y = dann$y * length(xann) * diff(hann$breaks)[1], lwd = 2,col="red")
}else{
ldAn<-0}

#not annotated
if(!is.na(data1_nAnn)){
 data_nAnn<-subset(data1_nAnn,V3<1000)
 ldnAn<-nrow(subset(data1_nAnn,V3>=1000))
 dnAnn<-density(data_nAnn[,3])
 xnAnn<-data_nAnn[,3]
 hnAnn<-hist(data_nAnn[,3], breaks=seq(0,1000, by=10),plot="FALSE")
 plot(hnAnn, col="green",add=T)
 lines(x = dnAnn$x, y = dnAnn$y * length(xnAnn) * diff(hnAnn$breaks)[1], lwd = 2,col="green")
}else{
ldnAn<-0}

legend("topright", c(paste("All proteins, ",ld," with length>1000"),paste("Annotated proteins, ",ldAn," with length>1000"),paste("Not annotated proteins, ",ldnAn," with length>1000")),col=c("blue","red","green"),pch=19)

dev.off()

