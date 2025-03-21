
/* Authors: Miguel Cardenas-Montes (1)
            Rafael Ponce (2)
            Ignacio Sevilla (3)

(1): miguel.cardenas@ciemat.es
(2): rafael.ponce@ciemat.es
(3): ignacio.sevilla@ciemat.es

NOTE: This code has been successfully tested on NVIDIA GTX295, C1060, C2050, C2070 and GT555M. The latter is a gaming GPU, for this reason does not accept too many points */

               /* TO COMPILE: IT'S CLEAR THAT COMPILATION DEPENDS ON YOUR PLATFORM */

/* For Ubuntu with Cuda Libraries you have to do once:

    user@user:yourpath$ nvcc -c -arch=sm_20 GP2PCF_GPU_v0.2.cu
    user@user:yourpath$ g++ -lcudart GP2PCF_GPU_v0.2.o -o GP2PCF_GPU

    NOTE: Sometimes could be necesary to do: (m value depend on your architecture, 32 bits or 64 bits)
        nvcc -c -m=32 -arch=sm_20 GP2PCF_GPU_v0.2.cu   or
        nvcc -c -m=64 -arch=sm_20 GP2PCF_GPU_v0.2.cu


        If you have to indicate where the libraries are you will have to do something like that:

        nvcc -arch=sm_20 GP2PCF_GPU_v0.2.cu
        g++ -lcudart -lpthread -L/usr/local/cuda/lib64 GP2PCF_GPU_v0.2.o -o GP2PCF_GPU.cu


Now, if everything went well, you just created a binary file called "GP2PCF_GPU" */


                                            /* TO RUN */

/* This program calculates the 2pt-angular auto-correlation and cross-correlation functions by brute force using a GPU
The program receives as input parameters the following:

    Catalog_1: The path of your galaxy catalog, usually is a galaxy catalog for a specific redshift bin
    Catalog_2: The path of the same galaxy catalog you put as the first input (if you want to do the auto-correlation function) or another galaxy catalog (if you want to do the cross-correlation function between two redshift bins) 
    Random_catalog: The path corresponding to the random catalog
    Number_of_points: It's the number of bins per degree that you want
    Output_correlation_file: The path of your output file 

And the program will return inside the output file six or seven columns, depend on whether you did the auto-correlation or the cross-correlation function.

The input files must have only two columns:

    RA: Right Ascension in degrees 
    DEC: Declination also in degrees

The output will be:

    For the auto-correlation:

    angle(degrees) 
    W(corr-func.) 
    Poissonian Error 
    Real-Real Pairs 
    Real-Rand Pairs 
    Rand-Rand Pairs

    For the cross-correlation:

    angle(degrees) 
    W(corr-func.) 
    Poissonian Error 
    Real_1-Real_2 Pairs 
    Real_1-Rand Pairs 
    Real_2-Rand Pairs
    Rand-Rand Pairs

To run the program:

If you want to do calculate the auto-correlation you must do:

        ./GP2PCF_GPU Catalog_1.txt Catalog_1.txt Random_cat.txt points output.txt

If you want to do an cross-correlation you must do:

        ./GP2PCF_GPU Catalog_1.txt Catalog_2.txt Random_cat.txt points output.txt

EXAMPLES TO CALL THE FUNCTION:

   To do the correlation with 16 points per degree

       ./GP2PCF_GPU test.cat test.cat test_rand.cat 16 W_auto_test.txt

   To do cross-correlation with 32 points per degree

       ./GP2PCF_GPU test.cat test2.cat test_rand.cat 32 W_cross_test.txt    


IMPORTANT: 

1.- Note that if the first and second file have the same name, the program will calculate the auto-correlation function. If not, the program will calculate the cross-correlation function

2.- For memory reasons the points per degree should be between 4 points and 64 points and it must be multiple of 4.

3.- For hardware limitations, there is a relationship between the points per degree and the degree you can reach. You can see this relationship in the next table

Points	Angle
4	64
8	32
16	16
32	8
64	4 */


/* Header files */

#include <string.h>
#include <time.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <cuda.h>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <iostream>
#include <fstream>
#include "sys/time.h"
#include <assert.h>
#include <sm_20_atomic_functions.h>


/* Constants */

#define threads 256 /* It's the number of threads we are going to use per block on the GPU */

using namespace std;


/* Kernels */

/* This kernel counts the number of pairs in the data file */
/* We will use this kernel to calculate real-real pairs and random-random pairs */

__global__ void binning(float *xd,float *yd,float *zd,float *ZZ,int number_lines,int points_per_degree, int number_of_degrees)
{

    /* We define variables (arrays) in shared memory */

    __shared__ float angle[threads];
    __shared__ float temp[threads];

    /* We define an index to run through these two arrays */    

    int index = threadIdx.x;

    /* This variable is necesary to accelerate the calculation, it's due that "temp" was definied in the shared memory too */

    temp[index]=0;
    float x,y,z; //MCM
    float xx,yy,zz; //MCM

    /* We start the counting */

    for (int i=0;i<number_lines;i++)
    {
        int dim_idx =  blockIdx.x * blockDim.x + threadIdx.x;
        x = xd[i];//MCM
        y = yd[i];//MCM
        z = zd[i];//MCM

        /* The "while" replaces the second for-loop in the sequential calculation case (CPU). We use "while" rather than "if" as recommended in the book "Cuda by Example" */

        while (dim_idx < number_lines)
        {
            xx = xd[dim_idx];//MCM
            yy = yd[dim_idx];//MCM
            zz = zd[dim_idx];//MCM

            /* We make the dot product */ 
            angle[index] = x * xx + y * yy + z * zz;//MCM


            //angle[index]=xd[i]*xd[dim_idx]+yd[i]*yd[dim_idx]+zd[i]*zd[dim_idx];//MCM
            //__syncthreads();//MCM

            /* Sometimes "angle" is higher than one, due to numnerical precision, to solve it we use the next sentence */

            angle[index]=fminf(angle[index],1.0);
            angle[index]=acosf(angle[index])*180.0/M_PI;
            //__syncthreads();//MCM

            /* We finally count the number of pairs separated an angular distance "angle", always in shared memory */

            if(angle[index] < number_of_degrees)
            {
                atomicAdd( &temp[int(angle[index]*points_per_degree)], 1.0);
            }
            __syncthreads();
            dim_idx = blockDim.x * gridDim.x+dim_idx;
        }
    }

    /* We copy the number of pairs from shared memory to global memory */

    atomicAdd( &ZZ[threadIdx.x] , temp[threadIdx.x]);
    __syncthreads();
}

/* This kernel counts the number of pairs that there are between two data groups */
/* We will use this kernel to calculate real-random pairs and real_1-real_2 pairs (cross-correlation) */
/* NOTE that this kernel has NOT been merged with 'binning' above: this is for speed optimization, we avoid passing extra variables to the GPU */ 

__global__ void binning_mix(float *xd_real, float *yd_real, float *zd_real, float *xd_sim, float *yd_sim, float *zd_sim, float *ZY, int lines_number_1, int lines_number_2, int points_per_degree, int number_of_degrees)
{

    /* We define variables (arrays) in shared memory */

    __shared__ float angle[threads];
    __shared__ float temp[threads];

    /* We define an index to run through these two arrays */    

    int index = threadIdx.x;

    /* This variable is necesary to accelerate the calculation, it's due that "temp" was definied in the shared memory too */

    temp[index]=0;
    float x,y,z; //MCM
    float xx,yy,zz; //MCM

    /* We start the counting */

    for (int i=0;i<lines_number_1;i++)
    {
        int dim_idx =  blockIdx.x * blockDim.x + threadIdx.x;
        x = xd_real[i];//MCM
        y = yd_real[i];//MCM
        z = zd_real[i];//MCM

        /* The "while" replaces the second for-loop in the sequential calculation case (CPU). We use "while" rather than "if" as recommended in the book "Cuda by Example" */

        while (dim_idx < lines_number_2)
        {
            xx = xd_sim[dim_idx];//MCM
            yy = yd_sim[dim_idx];//MCM
            zz = zd_sim[dim_idx];//MCM
            /* We make the dot product */ 
            angle[index] = x * xx + y * yy + z * zz;//MCM

            //angle[index]=xd[i]*xd[dim_idx]+yd[i]*yd[dim_idx]+zd[i]*zd[dim_idx];//MCM
            //__syncthreads();//MCM

            /* Sometimes "angle" is higher than one, due to numnerical precision, to solve it we use the next sentence */
            
            angle[index]=fminf(angle[index],1.0);
            angle[index]=acosf(angle[index])*180.0/M_PI;
            //__syncthreads();//MCM

            /* We finally count the number of pairs separated an angular distance "angle", always in shared memory */

            if(angle[index] < number_of_degrees)
            {
                atomicAdd( &temp[int(angle[index]*points_per_degree)], 1.0);
            }
            __syncthreads();
            dim_idx = blockDim.x * gridDim.x+dim_idx;
        }
    }

    /* We copy the number of pairs from shared memory to global memory */

    atomicAdd( &ZY[threadIdx.x] , temp[threadIdx.x]);
    __syncthreads();
}



/* This function counts the number of columns in a file */
/* NOTE that this is done only checking the first row */


int cols_number(char *input_file)
{

    /* Definition of Variables */

    char row[650];
    char * pch;
    int columns=0;

    /* Opening the input file */

    std::ifstream f_in(input_file, std::ios::in);

    /* Reading the first line */

    f_in.getline(row,650,'\n');

    /* Closing file */

    f_in.close();

    /* Counting columns */

    pch = strtok (row,"'\t'' '");
    while (pch != NULL)
    {
        columns++;
        pch = strtok (NULL, "'\t'' '");
    }
    return (columns);
}

/* This function counts the number of rows in a file */

int counting_lines(char *input_file)
{

    /* Definition of variables */

    int lines=0;
    char line[650];

    /* Opening the input file */

    std::ifstream f_in;
    f_in.open(input_file, std::ios::in);

    /* Counting lines */

    while(!f_in.eof())
    {
        if(f_in.getline(line, 650, '\n' ) != NULL)
        {
            lines=lines+1;
        }
    }
    lines=lines-1;

    /* Closing file */

    f_in.close();
    
    return(lines);
}

/* This function checks the input data */

int verification(int argc, char *argv[])
{

    /* Definition of variables */
   
    int points_per_degree;
    int columns;
    int f;

    /* Opening, checking and closing the first input file */

    std::ifstream fileinputdata;
    for(f=1;f<4;f++){
        fileinputdata.open(argv[f], std::ios::in);
        if (fileinputdata == NULL)
        {
            printf("Error opening data file number %d \n",f);
            return(0);
        }
        fileinputdata.close();
    }

    /* Checking other input parameters */

    if (argv[4]==NULL)
    {
        printf("You must introduce a number of points that you want per degree");
        return(0);
    }

    points_per_degree=atoi(argv[4]);
 

    if (points_per_degree<4 or points_per_degree%4!=0 or points_per_degree>64)
    {
        printf("The points per degree must be [4,8,16,32,64]");
        return(0);
    }

    if (argv[5]==NULL)
    {
        printf("You must introduce a name for the output file");
        return(0);
    }

    /* Checking cols number in every input file */

    for(f=1;f<4;f++){
        columns=cols_number(argv[f]);
        if (columns != 2 )
        {
            printf("Number of columns in file number %d must be exactly 2 and the first one has to be the right ascension and the second one the declination, both in degrees",f);
            return(0);
        }
    }

    return(1);
}

/* This function lets the program knows if you want to do a cross-correlation or a auto-correlation function */

/* This function checks if the name of the first two input files are the same. If the name is the same for both, the program makes the auto-correlation, if not, the program makes the cross-correlation */

int cross_auto(int argc, char *argv[])
{
    if(strcmp(argv[1],argv[2])==0)
    {
        return(0); /*auto*/
    }
    else
    {
        return(1); /*cross*/
    }

}

/* Equatorial to cartesian conversion */ 

int eq2cart(char *filename, int nlines, float *xd, float *yd, float *zd){
        std::ifstream infile(filename);
        int n;
        float ra, dec, phi, cth, th;

        /* We will store the data in cartesian coordinates, that's why we pass the ecuatorial coordinates to spheric coordinates and then to cartesian coordinates */

        for (n=0;n<nlines;n++)
        {
            infile>>ra>>dec; /* reading ecuatorial coordinates */
            phi=ra*M_PI/180.0;
            cth=cos((90.0-dec)*M_PI/180.0);
            th=acos(cth);

            /* to cartesian coordinates */
            
            xd[n]=cos(phi)*sin(th);
            yd[n]=sin(phi)*sin(th);
            zd[n]=cth;    
        }

        infile.close();
        
        return(0);
}

int copy2dev(float *gpu_xd, float *gpu_yd, float *gpu_zd, float *xd, float *yd, float *zd, int lines_number, float *gpu_ZZ, float *ZZ, dim3 dimGrid, int points_per_degree, int number_of_degrees){
         /* We copy the data in cartesian coordinates to the GPU */  

        cudaMemcpy(gpu_xd,xd,lines_number*sizeof(float),cudaMemcpyHostToDevice);
        cudaMemcpy(gpu_yd,yd,lines_number*sizeof(float),cudaMemcpyHostToDevice);
        cudaMemcpy(gpu_zd,zd,lines_number*sizeof(float),cudaMemcpyHostToDevice);

        /* We initialize pair variable (ZZ) on GPU, copying the initialize data on CPU */

        cudaMemcpy(gpu_ZZ, ZZ, threads*sizeof(float),cudaMemcpyHostToDevice);

        /* We call the needed kernel to calculate the number of pairs */ 

        binning <<< dimGrid, threads >>> (gpu_xd, gpu_yd, gpu_zd, gpu_ZZ, lines_number, points_per_degree, number_of_degrees);

        /* We recover the real pairs variables (DD) */

        cudaMemcpy(ZZ, gpu_ZZ, threads*sizeof(float),cudaMemcpyDeviceToHost);
       
        return(0);
}

int copy2dev_mix(float *gpu_xd_1, float *gpu_yd_1, float *gpu_zd_1, float *xd_1, float *yd_1, float *zd_1, int lines_number_1, float *gpu_xd_2, float *gpu_yd_2, float *gpu_zd_2, float *xd_2, float *yd_2, float *zd_2, int lines_number_2, float *gpu_ZY, float *ZY, dim3 dimGrid, int points_per_degree, int number_of_degrees){

        /* We copy again the real data and the random data in cartesian coordinates to the GPU. This step is not necesary, but it's recommended because we ensure there won't be any trouble with the memory on the GPU */

        /* We copy the real data and random data to make the correlation between both */

        cudaMemcpy(gpu_xd_1,xd_1,lines_number_1*sizeof(float),cudaMemcpyHostToDevice);
        cudaMemcpy(gpu_yd_1,yd_1,lines_number_1*sizeof(float),cudaMemcpyHostToDevice);
        cudaMemcpy(gpu_zd_1,zd_1,lines_number_1*sizeof(float),cudaMemcpyHostToDevice);
        cudaMemcpy(gpu_xd_2,xd_2,lines_number_2*sizeof(float),cudaMemcpyHostToDevice);
        cudaMemcpy(gpu_yd_2,yd_2,lines_number_2*sizeof(float),cudaMemcpyHostToDevice);
        cudaMemcpy(gpu_zd_2,zd_2,lines_number_2*sizeof(float),cudaMemcpyHostToDevice);

        /* We initialize real-random pair variable (ZY) on GPU, copying the initialize data on CPU */

        cudaMemcpy(gpu_ZY,ZY,threads*sizeof(float),cudaMemcpyHostToDevice);

        /* We call the needed kernel to calculate the number of pairs that there are between the real data and the random data */

        binning_mix <<< dimGrid, threads >>> (gpu_xd_1, gpu_yd_1, gpu_zd_1, gpu_xd_2, gpu_yd_2, gpu_zd_2, gpu_ZY, lines_number_1, lines_number_2, points_per_degree, number_of_degrees);

        /* We recover the real-random pairs variables (ZY) */

        cudaMemcpy(ZY,gpu_ZY,threads*sizeof(float),cudaMemcpyDeviceToHost);

        return(0);
}

/* Main Function*/

int main(int argc, char *argv[])
{
  
    /* Checking if the input files and call to script meet the requirements */

    if (verification(argc, argv)==0)
    {
        exit(1);
    }

    /* Definition of variables, these variables are the same for the auto-correlation and the cross-correlation */

    int points_per_degree;
    int number_of_degrees;
    char *input_real_file_1, *input_real_file_2, *input_random_file, *output_file;
    double W, angle_theta, poissonian_error, norm_cost_1, norm_cost_2;

    int real_lines_number_1, real_lines_number_2, random_lines_number, max_lines;

    float *xd_real_1,*yd_real_1,*zd_real_1;
    float *xd_real_2,*yd_real_2,*zd_real_2;
    float *xd_rand,*yd_rand,*zd_rand;
   
    float *gpu_xd_real_1;
    float *gpu_yd_real_1;
    float *gpu_zd_real_1;
    float *gpu_xd_real_2;
    float *gpu_yd_real_2;
    float *gpu_zd_real_2;
    float *gpu_xd_rand;
    float *gpu_yd_rand;
    float *gpu_zd_rand;

    /* Assignment of Variables with inputs */

    input_real_file_1=argv[1];
    input_real_file_2=argv[2];
    input_random_file=argv[3];
    points_per_degree=atoi(argv[4]);
    number_of_degrees=int(float(threads)/float(points_per_degree));
    output_file=argv[5];

    /* Counting lines in every input file */
        
    real_lines_number_1=counting_lines(input_real_file_1);
    random_lines_number=counting_lines(input_random_file);
    if (cross_auto(argc,argv)==1) real_lines_number_2=counting_lines(input_real_file_2);
  
    /* We define variables to store the real,random data */

    xd_real_1 = (float *)malloc(real_lines_number_1 * sizeof (float));
    yd_real_1 = (float *)malloc(real_lines_number_1 * sizeof (float));
    zd_real_1 = (float *)malloc(real_lines_number_1 * sizeof (float));
    xd_rand = (float *)malloc(random_lines_number * sizeof (float));
    yd_rand = (float *)malloc(random_lines_number * sizeof (float));
    zd_rand = (float *)malloc(random_lines_number * sizeof (float));
    
    if (cross_auto(argc,argv)==1)
    {
        xd_real_2 = (float *)malloc(real_lines_number_2 * sizeof (float));
        yd_real_2 = (float *)malloc(real_lines_number_2 * sizeof (float));
        zd_real_2 = (float *)malloc(real_lines_number_2 * sizeof (float));       
    }

    /* Opening the first input file */        

    eq2cart(input_real_file_1,real_lines_number_1,xd_real_1,yd_real_1,zd_real_1);

    /* Opening the second input file */        

    if (cross_auto(argc,argv)==1)
    {
        eq2cart(input_real_file_2,real_lines_number_2,xd_real_2,yd_real_2,zd_real_2);
    }

    /* Opening the third input file */        

    eq2cart(input_random_file,random_lines_number,xd_rand,yd_rand,zd_rand);

    /* We define variables to send to the GPU */

    /* For real data */

    cudaMalloc( (void**)&gpu_xd_real_1,real_lines_number_1 * sizeof(float));
    cudaMalloc( (void**)&gpu_yd_real_1,real_lines_number_1 * sizeof(float));
    cudaMalloc( (void**)&gpu_zd_real_1,real_lines_number_1 * sizeof(float));
    if (cross_auto(argc,argv)==1)
    {
        cudaMalloc( (void**)&gpu_xd_real_2,real_lines_number_2 * sizeof(float));
        cudaMalloc( (void**)&gpu_yd_real_2,real_lines_number_2 * sizeof(float));
        cudaMalloc( (void**)&gpu_zd_real_2,real_lines_number_2 * sizeof(float));
    }

    /* For random data */

    cudaMalloc( (void**)&gpu_xd_rand,random_lines_number * sizeof(float));
    cudaMalloc( (void**)&gpu_yd_rand,random_lines_number * sizeof(float));
    cudaMalloc( (void**)&gpu_zd_rand,random_lines_number * sizeof(float));
  
    /* We define variables to store the pairs between real data (DD), random data (RR) and both together (DR) */
  
    /* on CPU */
    float *DD;
    float *DR;
    float *RR;
    float *D1D2;
    float *D1R;
    float *D2R;
    RR = (float *)malloc(threads*sizeof(float));
    if (cross_auto(argc,argv)==1)
    {
        D1D2 = (float *)malloc(threads*sizeof(float));
        D1R = (float *)malloc(threads*sizeof(float));
        D2R = (float *)malloc(threads*sizeof(float));
        for (int i=0; i< threads; i++)
        {
            D1D2[i] = 0.0;
            RR[i] = 0.0;
            D1R[i] = 0.0;
            D2R[i] = 0.0;
        }
    }
    else
    {
        DD = (float *)malloc(threads*sizeof(float));
        DR = (float *)malloc(threads*sizeof(float));
        for (int i=0; i< threads; i++)
        {
           DD[i] = 0.0;
           RR[i] = 0.0;
           DR[i] = 0.0;
        }
    }

    /* on GPU */
    float *gpu_DD;
    float *gpu_DR;
    float *gpu_RR;
    float *gpu_D1D2;
    float *gpu_D1R;
    float *gpu_D2R;
    cudaMalloc( (void**)&gpu_RR, threads*sizeof(float));
    if (cross_auto(argc,argv)==1)
    {
        cudaMalloc( (void**)&gpu_D1D2, threads*sizeof(float));
        cudaMalloc( (void**)&gpu_D1R, threads*sizeof(float));
        cudaMalloc( (void**)&gpu_D2R, threads*sizeof(float));            
    }
    else
    {
        cudaMalloc( (void**)&gpu_DD, threads*sizeof(float));
        cudaMalloc( (void**)&gpu_DR, threads*sizeof(float));
    }

    /* We determine which is the maximum number of lines */
    max_lines = max(real_lines_number_1,random_lines_number);
    if (cross_auto(argc,argv)==1)
    {
        max_lines = max(max_lines,real_lines_number_2);            
    }
        
    /* We define the GPU-GRID size, it's really the number of blocks we are going to use on the GPU */

    dim3 dimGrid((max_lines/threads)+1);
  
    if (cross_auto(argc,argv)==1)
    {
        copy2dev(gpu_xd_rand,gpu_yd_rand,gpu_zd_rand,xd_rand,yd_rand,zd_rand,random_lines_number,gpu_RR,RR,dimGrid,points_per_degree,number_of_degrees);
        copy2dev_mix(gpu_xd_real_1,gpu_yd_real_1,gpu_zd_real_1,xd_real_1,yd_real_1,zd_real_1,real_lines_number_1,gpu_xd_real_2,gpu_yd_real_2,gpu_zd_real_2,xd_real_2,yd_real_2,zd_real_2,real_lines_number_2,gpu_D1D2,D1D2,dimGrid,points_per_degree,number_of_degrees);        
        copy2dev_mix(gpu_xd_real_1,gpu_yd_real_1,gpu_zd_real_1,xd_real_1,yd_real_1,zd_real_1,real_lines_number_1,gpu_xd_rand,gpu_yd_rand,gpu_zd_rand,xd_rand,yd_rand,zd_rand,random_lines_number,gpu_D1R,D1R,dimGrid,points_per_degree,number_of_degrees);        
        copy2dev_mix(gpu_xd_real_2,gpu_yd_real_2,gpu_zd_real_2,xd_real_2,yd_real_2,zd_real_2,real_lines_number_2,gpu_xd_rand,gpu_yd_rand,gpu_zd_rand,xd_rand,yd_rand,zd_rand,random_lines_number,gpu_D2R,D2R,dimGrid,points_per_degree,number_of_degrees);        
    }
    else
    {
        copy2dev(gpu_xd_real_1,gpu_yd_real_1,gpu_zd_real_1,xd_real_1,yd_real_1,zd_real_1,real_lines_number_1,gpu_DD,DD,dimGrid,points_per_degree,number_of_degrees);
        copy2dev(gpu_xd_rand,gpu_yd_rand,gpu_zd_rand,xd_rand,yd_rand,zd_rand,random_lines_number,gpu_RR,RR,dimGrid,points_per_degree,number_of_degrees);
        copy2dev_mix(gpu_xd_real_1,gpu_yd_real_1,gpu_zd_real_1,xd_real_1,yd_real_1,zd_real_1,real_lines_number_1,gpu_xd_rand,gpu_yd_rand,gpu_zd_rand,xd_rand,yd_rand,zd_rand,random_lines_number,gpu_DR,DR,dimGrid,points_per_degree,number_of_degrees);        
    }

    /* Opening the output file */		

    std::ofstream f_out(output_file);

   /* We calculate the normalization factor */

   norm_cost_1=float(random_lines_number)/float(real_lines_number_1);
   if (cross_auto(argc,argv)==1)
   {
       norm_cost_2=float(random_lines_number)/float(real_lines_number_2);
   }

   if (cross_auto(argc,argv)==1)
   { 

        for (int i=1;i<threads;i++)
        {
            /* The angle corresponding to the W value */

            angle_theta=(1.0/points_per_degree)/2.0+(i*(1.0/points_per_degree));              

            /* We are calculating the Landy & Szalay estimator */
            
            W=(norm_cost_1)*(norm_cost_2)*(D1D2[i]/RR[i])-(norm_cost_1)*(D1R[i]/RR[i])-(norm_cost_2)*(D2R[i]/RR[i])+1.0;
            poissonian_error=(1.0+W)/sqrt(D1D2[i]);
            f_out<<angle_theta<<"\t"<<W<<"\t"<<poissonian_error<<"\t"<<D1D2[i]<<"\t"<<D1R[i]<<"\t"<<D2R[i]<<"\t"<<RR[i]<<endl;
        }
    }
    else
    {
        for (int i=0;i<threads;i++)
        {
            /* The angle corresponding to the W value */

            angle_theta=(1.0/points_per_degree)/2.0+(i*(1.0/points_per_degree));
            W=(((pow(norm_cost_1,2)*DD[i])-(2*norm_cost_1*DR[i]))/RR[i])+1.0;
            poissonian_error=(1.0+W)/sqrt(DD[i]);
            f_out<<angle_theta<<"\t"<<W<<"\t"<<poissonian_error<<"\t"<<DD[i]<<"\t"<<DR[i]<<"\t"<<RR[i]<<endl;
        } 
    }
  
    /* Closing output files */

    f_out.close();

    /* Freeing memory on the GPU */

    cudaFree( gpu_xd_rand );
    cudaFree( gpu_yd_rand );
    cudaFree( gpu_zd_rand );
    cudaFree( gpu_xd_real_1 );
    cudaFree( gpu_yd_real_1 );
    cudaFree( gpu_zd_real_1 );
    
    if (cross_auto(argc,argv)==1)
    {
        cudaFree( gpu_xd_real_2 );
        cudaFree( gpu_yd_real_2 );
        cudaFree( gpu_zd_real_2 );
        cudaFree( gpu_D1D2 );
        cudaFree( gpu_D1R );
        cudaFree( gpu_D2R );
    }
    else
    {

        cudaFree( gpu_DD );
        cudaFree( gpu_DR );
        cudaFree( gpu_RR );
    }

    /* Freeing memory on the CPU */

    free(xd_real_1);
    free(yd_real_1);
    free(zd_real_1);
    free(xd_rand);
    free(yd_rand);
    free(zd_rand);

    if (cross_auto(argc,argv)==1)
    {
        free(xd_real_2);
        free(yd_real_2);
        free(zd_real_2);
        free(D1D2);
        free(D1R);
        free(D2R);
    }
    else
    {
        free(DD);
        free(DR);
        free(RR);
    }
    
    return(0);
}
