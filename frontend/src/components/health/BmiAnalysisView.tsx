import { useCallback, useEffect, useState } from "react";
import { Scale, CheckCircle2, ArrowUpRight, ArrowDownRight, RefreshCw, Globe } from "lucide-react";
import { useAuthStore } from "@/store/authStore";
import { healthApi } from "@/api/services";
import type { BmiAnalysisInput, BmiAnalysisResult, BmiTimeSeriesRecord } from "@/types/health";
import BmiFormCard from "./BmiFormCard";
import BmiTimeSeriesBoard from "./BmiTimeSeriesBoard";
import BmiHistoryTable from "./BmiHistoryTable";
import MedicalAlertBanner from "./MedicalAlertBanner";
import WeightGainChart from "./WeightGainChart";
import DietPlanCard from "./DietPlanCard";
import LifestyleCareCard from "./LifestyleCareCard";
import SearXNGConfigModal from "./SearXNGConfigModal";

export default function BmiAnalysisView() {
  const { user } = useAuthStore();
  const [loading, setLoading] = useState<boolean>(false);
  const [result, setResult] = useState<BmiAnalysisResult | null>(null);
  const [toast, setToast] = useState<string>("");
  const [timeseries, setTimeseries] = useState<BmiTimeSeriesRecord[]>([]);
  const [historyLoading, setHistoryLoading] = useState<boolean>(true);
  const [deletingId, setDeletingId] = useState<number | null>(null);
  const [searxngModalOpen, setSearxngModalOpen] = useState<boolean>(false);
  const isAdmin = !!user?.is_staff;

  const showToast = (msg: string) => {
    setToast(msg);
    setTimeout(() => setToast(""), 2500);
  };

  /** 拉取全时序测量打卡历史（看板与历史表共用数据源） */
  const loadTimeseries = useCallback(async () => {
    setHistoryLoading(true);
    try {
      const data = await healthApi.getBmiTimeseries();
      setTimeseries(data?.timeseries || []);
    } catch {
      setTimeseries([]);
    } finally {
      setHistoryLoading(false);
    }
  }, []);

  useEffect(() => {
    loadTimeseries();
  }, [loadTimeseries]);

  const handleAnalyze = async (data: BmiAnalysisInput) => {
    setLoading(true);
    try {
      const res = await healthApi.analyzeBmi(data);
      setResult(res);
      // 分析打卡已自动持久化，优先直接采用响应内带回的最新时序，失败再回源拉取
      if (res?.timeseries) {
        setTimeseries(res.timeseries);
      } else {
        loadTimeseries();
      }
      showToast("分析完成！已为您生成专属医学达标报告与个性化方案");
    } catch (err: any) {
      showToast(err.message || "分析请求失败，请稍后重试");
    } finally {
      setLoading(false);
    }
  };

  /** 删除历史打卡记录（后端二次权限校验），删除后联动刷新看板 */
  const handleDeleteRecord = async (id: number) => {
    setDeletingId(id);
    try {
      await healthApi.remove(id);
      showToast("打卡记录已删除，图表看板已联动刷新");
      await loadTimeseries();
    } catch (err: any) {
      showToast(err.message || "删除失败，请稍后重试");
    } finally {
      setDeletingId(null);
    }
  };

  const evalData = result?.evaluation;
  const isGainNormal = evalData?.gain_status === "normal";
  const isGainBelow = evalData?.gain_status === "below";

  return (
    <div className="space-y-6">
      {/* 模块头部说明卡 */}
      <div className="rounded-2xl border border-orange-100/80 bg-gradient-to-r from-orange-50/70 via-warm/50 to-white p-5 shadow-2xs dark:border-gray-800 dark:from-gray-900 dark:via-gray-900/90 dark:to-gray-900">
        <div className="flex flex-wrap items-center justify-between gap-4">
          <div className="flex items-center gap-3">
            <div className="flex h-12 w-12 items-center justify-center rounded-2xl bg-brand-500 text-white shadow-md shadow-brand-500/20">
              <Scale className="h-6 w-6" />
            </div>
            <div>
              <h2 className="text-lg font-bold text-gray-800 dark:text-gray-100">
                孕产妇体重/BMI分析与个性化方案
              </h2>
              <p className="mt-0.5 text-xs text-gray-500 dark:text-gray-400">
                国家卫健委标准 (WS/T 801-2022) 临床增重曲线 · 平台与SearXNG双通道膳食推荐 · 剧吐及子痫风险筛查
              </p>
            </div>
          </div>

          <div className="flex items-center gap-2">
            {isAdmin && (
              <button
                onClick={() => setSearxngModalOpen(true)}
                className="btn-secondary gap-1.5 text-xs shadow-2xs"
              >
                <Globe className="h-3.5 w-3.5" /> SearXNG 引擎配置
              </button>
            )}

            {result && (
              <button
                onClick={() => setResult(null)}
                className="btn-secondary gap-1.5 text-xs shadow-2xs"
              >
                <RefreshCw className="h-3.5 w-3.5" /> 收起本次分析结果
              </button>
            )}
          </div>
        </div>
      </div>

      {/* 卡片 1: 测量录入与按天打卡 */}
      <BmiFormCard onSubmit={handleAnalyze} loading={loading} />

      {/* 卡片 2: 多维度时序图表看板（趋势折线 / 增量柱状 + 时间跨度筛选） */}
      <BmiTimeSeriesBoard records={timeseries} loading={historyLoading} />

      {/* 卡片 3: 测量打卡历史数据表 */}
      <BmiHistoryTable
        records={timeseries}
        loading={historyLoading}
        onDelete={handleDeleteRecord}
        deletingId={deletingId}
      />

      {/* 卡片 4: 医学预警与 AI 双通道食谱方案 */}
      {result && evalData && (
        <div className="space-y-6">
          {/* 4.1 医学异常预警 Banner */}
          <MedicalAlertBanner alerts={result.alerts || []} />

          {/* 4.2 核心指标概览看板 */}
          <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
            <div className="card space-y-1 p-4">
              <span className="text-xs text-gray-400">孕前 BMI</span>
              <div className="flex items-baseline gap-2">
                <span className="text-2xl font-extrabold text-gray-800 dark:text-gray-100">
                  {evalData.bmi}
                </span>
                <span className="text-xs font-semibold text-brand-600 dark:text-brand-400">
                  {evalData.category_label}
                </span>
              </div>
            </div>

            <div className="card space-y-1 p-4">
              <span className="text-xs text-gray-400">全孕期适宜总增重</span>
              <div className="flex items-baseline gap-1">
                <span className="text-2xl font-extrabold text-emerald-600 dark:text-emerald-400">
                  {evalData.recommended_total_gain_min} ~ {evalData.recommended_total_gain_max}
                </span>
                <span className="text-xs text-gray-500">kg</span>
              </div>
            </div>

            <div className="card space-y-1 p-4">
              <span className="text-xs text-gray-400">
                {evalData.stage_type === "postpartum" ? "产后滞留体重" : `当前孕${evalData.gestational_week}周适宜区间`}
              </span>
              <div className="flex items-baseline gap-1">
                <span className="text-2xl font-extrabold text-gray-800 dark:text-gray-100">
                  {evalData.current_week_target_min} ~ {evalData.current_week_target_max}
                </span>
                <span className="text-xs text-gray-500">kg</span>
              </div>
            </div>

            <div className="card space-y-1 p-4">
              <span className="text-xs text-gray-400">当前实测增重</span>
              <div className="flex items-center gap-1.5">
                <span
                  className={`text-2xl font-extrabold ${
                    isGainNormal
                      ? "text-emerald-600 dark:text-emerald-400"
                      : isGainBelow
                      ? "text-amber-500"
                      : "text-red-500"
                  }`}
                >
                  {evalData.actual_gain > 0 ? `+${evalData.actual_gain}` : evalData.actual_gain} kg
                </span>
                {isGainNormal ? (
                  <CheckCircle2 className="h-5 w-5 text-emerald-500" />
                ) : isGainBelow ? (
                  <ArrowDownRight className="h-5 w-5 text-amber-500" />
                ) : (
                  <ArrowUpRight className="h-5 w-5 text-red-500" />
                )}
              </div>
            </div>
          </div>

          {/* 4.3 WS/T 801-2022 标准全孕期曲线看板 */}
          {evalData.curve && evalData.curve.length > 0 && (
            <div className="card space-y-3">
              <div className="flex flex-wrap items-center justify-between gap-2 border-b border-orange-100/60 pb-2 dark:border-gray-800">
                <h3 className="text-sm font-bold text-gray-800 dark:text-gray-100">
                  国家卫健委 WS/T 801-2022 全孕期增重走势看板
                </h3>
                <span className="text-xs text-gray-400">
                  实线区域为达标区间 · 橙色点为您当前实测轨迹
                </span>
              </div>
              <WeightGainChart
                curve={evalData.curve}
                currentWeek={evalData.gestational_week}
                actualGain={evalData.actual_gain}
              />
            </div>
          )}

          {/* 4.4 双通道一日食谱卡片 */}
          {result.diet_plan && result.diet_plan.length > 0 && (
            <DietPlanCard
              meals={result.diet_plan}
              calorieBudget={evalData.recommended_weekly_gain}
              disclaimer={result.disclaimer}
            />
          )}

          {/* 4.5 运动与心理关怀卡片 */}
          <LifestyleCareCard advice={result.lifestyle_advice} />
        </div>
      )}

      {/* 管理员 SearXNG 私有化搜索引擎配置弹窗 */}
      <SearXNGConfigModal
        isOpen={searxngModalOpen}
        onClose={() => setSearxngModalOpen(false)}
        onSaved={() => showToast("SearXNG 引擎配置已更新并同步写入 .env")}
      />

      {/* Toast 提示 */}
      {toast && (
        <div className="fixed bottom-6 left-1/2 z-50 -translate-x-1/2 rounded-xl bg-gray-900/90 px-4 py-2 text-xs font-medium text-white shadow-lg backdrop-blur">
          {toast}
        </div>
      )}
    </div>
  );
}
