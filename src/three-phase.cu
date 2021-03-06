#include "gpu.h"
#include "three-phase.h"

// Номер среды
__constant__ int media = 0;
// Переломные точки насыщенностей при вычислении капиллярных давлений
__constant__ double S_w_range[2] = {0.1, 0.9};
__constant__ double S_g_range[2] = {0.1, 0.9};

// Функции вычисления эффективных значений насыщенностей
__device__ double device_assign_S_w_e(int local)
{
	return (DevArraysPtr->S_w[local] - gpu_def->S_wr[media]) / (1. - gpu_def->S_wr[media] - gpu_def->S_nr[media] - gpu_def->S_gr[media]);
}

__device__ double device_assign_S_n_e(int local)
{
	return (DevArraysPtr->S_n[local] - gpu_def->S_nr[media]) / (1. - gpu_def->S_wr[media] - gpu_def->S_nr[media] - gpu_def->S_gr[media]);
}

__device__ double device_assign_S_g_e(int local)
{
	return (DevArraysPtr->S_g[local] - gpu_def->S_gr[media]) / (1. - gpu_def->S_wr[media] - gpu_def->S_nr[media] - gpu_def->S_gr[media]);
}

// Вычисление капиллярных давлений
// Функции кап. давлений и их производных для центральной части интервала
__device__ double device_P_k_nw(double S)
{
	double A = gpu_def->lambda[media];
	return gpu_def->P_d_nw[media] * pow((pow(S, A / (1. - A)) - 1.), 1. / A);
}

__device__ double device_P_k_gn(double S)
{
	double A = gpu_def->lambda[media];
	return gpu_def->P_d_gn[media] * pow(pow((1. - S), A / (1. - A)) - 1., 1. / A);
}

__device__ double device_P_k_nw_S(double S)
{
	double A = gpu_def->lambda[media];
	return gpu_def->P_d_nw[media] * pow(pow(S, A / (1. - A)) - 1., 1. / A - 1.) * pow(S, (A / (1. - A) - 1.)) / (1. - A)
		/ (1. - gpu_def->S_wr[media] - gpu_def->S_nr[media] - gpu_def->S_gr[media]);
}

__device__ double device_P_k_gn_S(double S)
{
	double A = gpu_def->lambda[media];
	return gpu_def->P_d_gn[media] * pow(pow(1. - S, A / (1. - A)) - 1., 1. / A - 1.) * pow(1. - S, A / (1. - A) - 1.) / (1. - A)
		/ (1. - gpu_def->S_wr[media] - gpu_def->S_nr[media] - gpu_def->S_gr[media]);
}

// Функции вычисления капиллярных давлений и производных на всем интервале
// По краям интервала [0, 1] функции капиллярных давлений гладко заменяем линейными, производные меняются соответственно.
// Описание можно посмотреть в файле mathcad.
__device__ double device_assign_P_k_nw(double S_w_e)
{
	double Pk_nw = 0;

	if (S_w_e <= S_w_range[0])
	{
		Pk_nw = device_P_k_nw_S(S_w_range[0]) * (S_w_e - S_w_range[0]) + device_P_k_nw(S_w_range[0]);
	}
	else if (S_w_e >= S_w_range[1])
	{
		Pk_nw = device_P_k_nw_S(S_w_range[1]) * (S_w_e - S_w_range[1]) + device_P_k_nw(S_w_range[1]);;
	}
	else
	{
		Pk_nw = device_P_k_nw(S_w_e);
	}

	return Pk_nw;
}

__device__ double device_assign_P_k_gn(double S_g_e)
{
	double Pk_gn = 0;

	if (S_g_e <= S_g_range[0])
	{
		Pk_gn = device_P_k_gn_S(S_g_range[0]) * (S_g_e - S_g_range[0]) + device_P_k_gn(S_g_range[0]);
	}
	else if (S_g_e >= S_g_range[1])
	{
		Pk_gn = device_P_k_gn_S(S_g_range[1]) * (S_g_e - S_g_range[1]) + device_P_k_gn(S_g_range[1]);
	}
	else
	{
		Pk_gn = device_P_k_gn(S_g_e);
	}
	
	return Pk_gn;

}

// Функции вычисления производных капиллярных давлений по насыщенностям
__device__ double device_assign_P_k_nw_S(double S_w_e)
{
	double PkSw = 0;

	if (S_w_e <= S_w_range[0])
	{
		PkSw = device_P_k_nw_S(S_w_range[0]);
	}
	else if (S_w_e >= S_w_range[1])
	{
		PkSw = device_P_k_nw_S(S_w_range[1]);
	}
	else
	{
		PkSw = device_P_k_nw_S(S_w_e);
	}

	return PkSw;
}

__device__ double device_assign_P_k_gn_S(double S_g_e)
{
	double PkSn = 0;

	if (S_g_e <= S_g_range[0])
	{
		PkSn = (-1) * device_P_k_gn_S(S_g_range[0]);
	}
	else if (S_g_e >= S_g_range[1])
	{
		PkSn = (-1) * device_P_k_gn_S(S_g_range[1]);
	}
	else
	{
		PkSn = device_P_k_gn_S(S_g_e);
	}

	return PkSn;
}

// Функции вычисления относительных проницаемостей
__device__ double device_assign_k_w(double S_w_e)
{
	double A = gpu_def->lambda[media];
	double k_w = 0;

	if (S_w_e >= 1e-3)
	{
		k_w = pow(S_w_e, 0.5) * pow(1. - pow(1. - pow(S_w_e, A / (A - 1.)), (A - 1.) / A), 2.);
	}

	return k_w;
}

__device__ double device_assign_k_g(double S_g_e)
{
	double A = gpu_def->lambda[media];
	double k_g = 0;

	if (S_g_e >= 1e-3)
	{
		k_g = pow(S_g_e, 0.5) * pow(1. - pow(1. - S_g_e, A / (A - 1.)), 2. * (A - 1.) / A);
	}

	return k_g;
}

__device__ double device_assign_k_n(double S_w_e, double S_n_e)
{
	double A = gpu_def->lambda[media];
	double k_n = 0;
	double S_g_e = 1. - S_w_e - S_n_e;

	if (S_n_e >= 1e-3)
	{
		double k_n_w = pow(1. - S_w_e, 0.5) * pow(1. - pow(S_w_e, A / (A - 1.)), 2. * (A - 1.) / A);
		double k_n_g = pow(S_n_e, 0.5) * pow(1. - pow(1. - pow(S_n_e, A / (A - 1.)), (A - 1.) / A), 2.);
		k_n = S_n_e * k_n_w * k_n_g / (1 - S_w_e) / (1 - S_g_e);
	}

	return k_n;
}

//Функция вычисления значений давлений, плотностей и коэффициентов в законе Дарси в точке (i,j,k) среды media,
//исходя из известных значений основных параметров (Pw,Sw,Sn)
//1. Запоминаем, с какой именно из сред работаем
//2. Вычисление значения насыщенности фазы n из условия равенства насыщенностей в сумме единице
//3. Вычисление эффективных насыщенностей по формулам модели трехфазной фильтрации
//4. Вычисление относительных фазовых проницаемостей в соответствии с приближением Стоуна в модификации Азиза и Сеттари
//5. Вычисление капиллярных давлений в соответствии с приближенной моделью Паркера
//6. Вычисление фазовых давлений c помощью капиллярных
//7. Вычисление коэффициентов закона Дарси

__global__ void prepare_local_vars_kernel()
{
	int i = threadIdx.x + blockIdx.x * blockDim.x;
	int j = threadIdx.y + blockIdx.y * blockDim.y;
	int k = threadIdx.z + blockIdx.z * blockDim.z;

	if ((i < (gpu_def->locNx)) && (j < (gpu_def->locNy)) && (k < (gpu_def->locNz)))
	{
		int media = 0;
		double k_w, k_g, k_n, Pk_nw, Pk_gn;
		int local = i + j * (gpu_def->locNx) + k * (gpu_def->locNx) * (gpu_def->locNy);

		device_assign_S(local);

		double S_w_e = device_assign_S_w_e(local);
		double S_n_e = device_assign_S_n_e(local);
		double S_g_e = 1. - S_w_e - S_n_e;

		k_w = device_assign_k_w(S_w_e);
		k_g = device_assign_k_g(S_g_e);
		k_n = device_assign_k_n(S_w_e, S_n_e);

		Pk_nw = device_assign_P_k_nw(S_w_e);
		Pk_gn = device_assign_P_k_gn(S_g_e);

		DevArraysPtr->P_n[local] = DevArraysPtr->P_w[local] + Pk_nw;
		DevArraysPtr->P_g[local] = DevArraysPtr->P_n[local] + Pk_gn;

		device_assign_ro(local);

#ifdef ENERGY
		device_assign_H(local);
		device_assign_E_current(local);

		// Вынести в константы!!!
		double mu_w = 1. / (29.21 * DevArraysPtr->T[local] - 7506.64);
		double mu_n = 7.256E-10 * exp(4141.9 / DevArraysPtr->T[local]);
		double mu_g = 1.717E-5 * pow((DevArraysPtr->T[local] / 273.), 0.683);

		DevArraysPtr->Xi_w[local] = (-1.) * (gpu_def->K[media]) * k_w / mu_w;
		DevArraysPtr->Xi_n[local] = (-1.) * (gpu_def->K[media]) * k_n / mu_n;
		DevArraysPtr->Xi_g[local] = (-1.) * (gpu_def->K[media]) * k_g / mu_g;
#else
		DevArraysPtr->Xi_w[local] = (-1.) * (gpu_def->K[media]) * k_w / gpu_def->mu_w;
		DevArraysPtr->Xi_n[local] = (-1.) * (gpu_def->K[media]) * k_n / gpu_def->mu_n;
		DevArraysPtr->Xi_g[local] = (-1.) * (gpu_def->K[media]) * k_g / gpu_def->mu_g;
#endif

		device_test_positive(DevArraysPtr->P_n[local], __FILE__, __LINE__);
		device_test_positive(DevArraysPtr->P_g[local], __FILE__, __LINE__);
		device_test_nan(DevArraysPtr->Xi_w[local], __FILE__, __LINE__);
		device_test_nan(DevArraysPtr->Xi_n[local], __FILE__, __LINE__);
		device_test_nan(DevArraysPtr->Xi_g[local], __FILE__, __LINE__);
	}
}

//Функция решения системы 3*3 на основные параметры (Pn,Sw,Sg) методом Ньютона в точке (i,j,k) среды media
//1. Вычисление эффективных насыщенностей
//2. Переобозначение степенного коэффициента
//3. Вычисление капиллярных давлений
//4. Вычисление насыщенности фазы n
//5. Нахождение значения трех функций системы
//6. Вычисление частных производных производных капиллярных давлений по насыщенностям
//7. Вычисление матрицы частных производных
//8. Вычисление детерминанта матрицы частных производных
//9. Получение решения системы методом Крамера в явном виде
#ifndef ENERGY
__global__ void Newton_method_kernel()
{
	int i = threadIdx.x + blockIdx.x * blockDim.x;
	int j = threadIdx.y + blockIdx.y * blockDim.y;
	int k = threadIdx.z + blockIdx.z * blockDim.z;

	if (GPU_INTERNAL_POINT)
	{
		double S_w_e, S_g_e, S_n_e, Pk_nw, Pk_gn, PkSw, PkSn, Sg, F1, F2, F3;
		double dF[9] = {0, 0, 0, 0, 0, 0, 0, 0, 0};

		int local = i + j * (gpu_def->locNx) + k * (gpu_def->locNx) * (gpu_def->locNy);

		for (int w = 1; w <= gpu_def->newton_iterations; w++)
		{
			S_w_e = device_assign_S_w_e(local);
			S_n_e = device_assign_S_n_e(local);
			S_g_e = 1. - S_w_e - S_n_e;

			Pk_nw = device_assign_P_k_nw(S_w_e);
			Pk_gn = device_assign_P_k_gn(S_g_e);
			PkSw = device_assign_P_k_nw_S(S_w_e);
			PkSn = device_assign_P_k_gn_S(S_g_e);

			Sg = 1. - DevArraysPtr->S_w[local] - DevArraysPtr->S_n[local];

			F1 = gpu_def->ro0_w * (1. + (gpu_def->beta_w) * (DevArraysPtr->P_w[local] - gpu_def->P_atm))
			     * DevArraysPtr->S_w[local] - DevArraysPtr->roS_w[local];
			F2 = gpu_def->ro0_n * (1. + (gpu_def->beta_n) * (DevArraysPtr->P_w[local] + Pk_nw - gpu_def->P_atm))
			     * DevArraysPtr->S_n[local] - DevArraysPtr->roS_n[local];
			F3 = gpu_def->ro0_g * (DevArraysPtr->P_w[local] + Pk_nw + Pk_gn) / gpu_def->P_atm
			     * Sg - DevArraysPtr->roS_g[local];

			// Матрица частных производных. Индексу от 0 до 8 соответствуют F1P, F1Sw, F1Sn, F2P, F2Sw, F2Sn, F3P, F3Sw, F3Sn
			dF[0] = gpu_def->ro0_w * gpu_def->beta_w * DevArraysPtr->S_w[local];
			dF[3] = gpu_def->ro0_n * gpu_def->beta_n * DevArraysPtr->S_n[local];
			dF[6] = gpu_def->ro0_g * Sg / gpu_def->P_atm;
			dF[1] = gpu_def->ro0_w * (1 + gpu_def->beta_w * (DevArraysPtr->P_w[local] - gpu_def->P_atm));
			dF[4] = gpu_def->ro0_n * (1. + (gpu_def->beta_n) * PkSw) * DevArraysPtr->S_n[local];
			dF[7] = (-1) * gpu_def->ro0_g * (DevArraysPtr->P_w[local] + Pk_nw + Pk_gn - Sg * (PkSn + PkSw)) / gpu_def->P_atm;
			dF[2] = 0;
			dF[5] = gpu_def->ro0_n * (1. + gpu_def->beta_n * (DevArraysPtr->P_w[local] + Pk_nw - gpu_def->P_atm));
			dF[8] = (-1) * gpu_def->ro0_g * (DevArraysPtr->P_w[local] + Pk_nw + Pk_gn - Sg * PkSn) / gpu_def->P_atm;

			device_reverse_matrix(dF, 3);

			DevArraysPtr->P_w[local] = DevArraysPtr->P_w[local]
			        - (dF[0] * F1 + dF[1] * F2 + dF[2] * F3);
			DevArraysPtr->S_w[local] = DevArraysPtr->S_w[local]
			        - (dF[3] * F1 + dF[4] * F2 + dF[5] * F3);
			DevArraysPtr->S_n[local] = DevArraysPtr->S_n[local]
			        - (dF[6] * F1 + dF[7] * F2 + dF[8] * F3);
		}

		device_test_S(DevArraysPtr->S_w[local], __FILE__, __LINE__);
		device_test_S(DevArraysPtr->S_n[local], __FILE__, __LINE__);
		device_test_positive(DevArraysPtr->P_w[local], __FILE__, __LINE__);
	}
}
#endif

//Задание граничных условий отдельно для (Sw,Sg),Pn

// Задание граничных условий с меньшим числом проверок, но с введением дополнительных переменных
__global__ void Border_S_kernel()
{
	int i = threadIdx.x + blockIdx.x * blockDim.x;
	int j = threadIdx.y + blockIdx.y * blockDim.y;
	int k = threadIdx.z + blockIdx.z * blockDim.z;

	if (GPU_BOUNDARY_POINT)
	{
		int local1 = device_set_boundary_basic_coordinate(i, j, k);
		int local = i + j * (gpu_def->locNx) + k * (gpu_def->locNx) * (gpu_def->locNy);

		if ((j != 0) || ((gpu_def->source) <= 0))
		{
			DevArraysPtr->S_w[local] = DevArraysPtr->S_w[local1];
			DevArraysPtr->S_n[local] = DevArraysPtr->S_n[local1];
		}

		if ((j == 0) && ((gpu_def->source) > 0))
		{
			DevArraysPtr->S_w[local] = gpu_def->S_w_gr;
			DevArraysPtr->S_n[local] = gpu_def->S_n_gr;
		}
		device_test_S(DevArraysPtr->S_w[local], __FILE__, __LINE__);
		device_test_S(DevArraysPtr->S_n[local], __FILE__, __LINE__);
	}
}

__global__ void Border_P_kernel()
{
	int i = threadIdx.x + blockIdx.x * blockDim.x;
	int j = threadIdx.y + blockIdx.y * blockDim.y;
	int k = threadIdx.z + blockIdx.z * blockDim.z;

	if (GPU_BOUNDARY_POINT)
	{
		int local1 = device_set_boundary_basic_coordinate(i, j, k);
		int local = i + j * (gpu_def->locNx) + k * (gpu_def->locNx) * (gpu_def->locNy);

		double S_w_e = device_assign_S_w_e(local1);
		double S_n_e = device_assign_S_n_e(local1);
		double S_g_e = 1. - S_w_e - S_n_e;

		double P_k_nw = device_assign_P_k_nw(S_w_e);
		double P_k_gn = device_assign_P_k_gn(S_g_e);

		// Если отдельно задаем значения на границах через градиент (условия непротекания)
		if ((j != 0) && (j != (gpu_def->locNy) - 1))
		{
			DevArraysPtr->P_w[local] = DevArraysPtr->P_w[local1];
			DevArraysPtr->P_n[local] = DevArraysPtr->P_w[local1] + P_k_nw;
			DevArraysPtr->P_g[local] = DevArraysPtr->P_w[local1] + P_k_nw + P_k_gn;
		
		}
		else if (j == 0)
		{
			DevArraysPtr->P_w[local] = 1.1 * gpu_def->P_atm;
			DevArraysPtr->P_n[local] = 1.1 * gpu_def->P_atm;
			DevArraysPtr->P_g[local] = 1.1 * gpu_def->P_atm;

			/*if((i > 0) && (i < (gpu_def->locNx) / 3 - 1) && (((gpu_def->locNz) < 2) || (k > 0) && (k < (gpu_def->locNz) / 3 - 1)))
			{
				//Открытая верхняя граница
				DevArraysPtr->P_w[local] = gpu_def->P_atm;
				DevArraysPtr->P_n[local] = gpu_def->P_atm;
				DevArraysPtr->P_g[local] = gpu_def->P_atm;
			}
			else*/
			/*{
				// Условия непротекания
				DevArraysPtr->P_w[local] = (DevArraysPtr->P_w[local1]
				- (gpu_def->ro0_w) * (gpu_def->g_const) * (gpu_def->hy) * (1. - (gpu_def->beta_w) * (gpu_def->P_atm))) 
					/ (1. + (gpu_def->beta_w) * (gpu_def->ro0_w) * (gpu_def->g_const) * (gpu_def->hy));
				DevArraysPtr->P_n[local] = (DevArraysPtr->P_w[local1]
				+ P_k_nw - (gpu_def->ro0_n) * (gpu_def->g_const) * (gpu_def->hy) * (1. - (gpu_def->beta_n) * (gpu_def->P_atm))) 
					/ (1. + (gpu_def->beta_n) * (gpu_def->ro0_n) * (gpu_def->g_const) * (gpu_def->hy));
				DevArraysPtr->P_g[local] = (DevArraysPtr->P_w[local1]
				+ P_k_nw + P_k_gn) / (1. + (gpu_def->ro0_g) * (gpu_def->g_const) * (gpu_def->hy) / (gpu_def->P_atm));
			}*/
		}
		else
		{
			DevArraysPtr->P_w[local] = gpu_def->P_atm;
			DevArraysPtr->P_n[local] = gpu_def->P_atm;
			DevArraysPtr->P_g[local] = gpu_def->P_atm;

			// Условия непротекания (normal u = 0)
/*#ifdef ENERGY
			DevArraysPtr->P_w[local] = (DevArraysPtr->P_w[local1]
			+ (gpu_def->ro0_w) * (gpu_def->g_const) * (gpu_def->hy) * (1. - (gpu_def->beta_w) * (gpu_def->P_atm))
			- (gpu_def->alfa_w) * (DevArraysPtr->T[local] - gpu_def->T_0))
				/ (1. - (gpu_def->beta_w) * (gpu_def->ro0_w) * (gpu_def->g_const) * (gpu_def->hy));
			DevArraysPtr->P_n[local] = (DevArraysPtr->P_w[local1]
			+ P_k_nw + (gpu_def->ro0_n) * (gpu_def->g_const) * (gpu_def->hy) * (1. - (gpu_def->beta_n) * (gpu_def->P_atm))
			- (gpu_def->alfa_n) * (DevArraysPtr->T[local] - gpu_def->T_0))
				/ (1. - (gpu_def->beta_n) * (gpu_def->ro0_n) * (gpu_def->g_const) * (gpu_def->hy));
			DevArraysPtr->P_g[local] = (DevArraysPtr->P_w[local1]
			+ P_k_nw + P_k_gn) / (1. - (gpu_def->ro0_g) * (gpu_def->g_const) * (gpu_def->hy) * (gpu_def->T_0)
				/ ((gpu_def->P_atm) * DevArraysPtr->T[local]));
#else
			DevArraysPtr->P_w[local] = (DevArraysPtr->P_w[local1]
			+ (gpu_def->ro0_w) * (gpu_def->g_const) * (gpu_def->hy) * (1. - (gpu_def->beta_w) * (gpu_def->P_atm))) 
				/ (1. - (gpu_def->beta_w) * (gpu_def->ro0_w) * (gpu_def->g_const) * (gpu_def->hy));
			DevArraysPtr->P_n[local] = (DevArraysPtr->P_w[local1]
			+ P_k_nw + (gpu_def->ro0_n) * (gpu_def->g_const) * (gpu_def->hy) * (1. - (gpu_def->beta_n) * (gpu_def->P_atm))) 
				/ (1. - (gpu_def->beta_n) * (gpu_def->ro0_n) * (gpu_def->g_const) * (gpu_def->hy));
			DevArraysPtr->P_g[local] = (DevArraysPtr->P_w[local1]
			+ P_k_nw + P_k_gn) / (1. - (gpu_def->ro0_g) * (gpu_def->g_const) * (gpu_def->hy) / (gpu_def->P_atm));
#endif*/
		}
		device_test_positive(DevArraysPtr->P_w[local], __FILE__, __LINE__);
		device_test_positive(DevArraysPtr->P_n[local], __FILE__, __LINE__);
		device_test_positive(DevArraysPtr->P_g[local], __FILE__, __LINE__);
	}
}

#ifdef ENERGY
// Задание граничных условий на температуру
__global__ void Border_T_kernel()
{
	int i = threadIdx.x + blockIdx.x * blockDim.x;
	int j = threadIdx.y + blockIdx.y * blockDim.y;
	int k = threadIdx.z + blockIdx.z * blockDim.z;

	if (GPU_BOUNDARY_POINT)
	{
		int local1 = device_set_boundary_basic_coordinate(i, j, k);
		int local = i + j * (gpu_def->locNx) + k * (gpu_def->locNx) * (gpu_def->locNy);

		if (j == 0)
		{
			DevArraysPtr->T[local] = 320;
		}
		//else if(j == (gpu_def->locNy) - 1)
		//{
		//	DevArraysPtr->T[local] = 273;
		//}
		else
		{
			// Будем считать границы области не теплопроводящими
			DevArraysPtr->T[local] = DevArraysPtr->T[local1];
		}

		device_test_positive(DevArraysPtr->T[local], __FILE__, __LINE__);
	}
}
#endif

// Является ли точка нагнетательной скважиной
__device__ int device_is_injection_well(int i, int j, int k)
{
		return 0;
}

// Является ли точка добывающей скважиной
__device__ int device_is_output_well(int i, int j, int k)
{
	return 0;
}

// Устанавливает значения втекаемых/вытекаемых жидкостей q_i на скважинах
__device__ void device_wells_q(int i, int j, int k, double* q_w, double* q_n, double* q_g)
{
	*q_w = 0.0;
	*q_g = 0.0;
	*q_n = 0.0;

/*	int local = i + j * (gpu_def->locNx) + k * (gpu_def->locNx) * (gpu_def->locNy);

	if (j == 1 && (DevArraysPtr->S_w[local] <= 0.6))
		*q_w = 1.0 * gpu_def->dt;
*/
}

