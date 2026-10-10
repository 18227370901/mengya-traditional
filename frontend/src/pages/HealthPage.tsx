import { useAuthStore } from "@/store/authStore";
import { useEffect, useState } from "react";
import { Baby, Calendar, CalendarCheck, LineChart, Plus, Trash2, Scale, HeartPulse } from "lucide-react";
import CopyButton from "@/components/CopyButton";
import { healthApi } from "@/api/services";
import type { HealthRecord } from "@/types";
import GrowthChart from "@/components/GrowthChart";
import VaccineCalendar from "@/components/VaccineCalendar";
import HealthCalendar from "@/components/HealthCalendar";
import BmiAnalysisView from "@/components/health/BmiAnalysisView";
import UnifiedHealthCheckIn from "@/components/health/UnifiedHealthCheckIn";

/**
 * 健康中心（v1.56 信息架构重构）
 * 按「对象 + 记录类型」组织为 4 个 Tab：
 * ① 妈妈·孕产档案（记录 + BMI 分析/看板/医学评估，合并原"孕产记录"+"体重/BMI分析"）
 * ② 宝宝·生长档案（生长曲线 + WHO 参考线 + 测量记录）
 * ③ 宝宝·疫苗计划（疫苗日历 + 接种状态 + 下一针建议）
 * ④ 健康时间轴（日历总览：按日聚合妈妈+宝宝全部记录，点击日期补录）
 */
type TabKey = "mom" | "growth" | "vaccine" | "calendar";

const TABS: Array<{ key: TabKey; label: string; icon: typeof CalendarCheck }> = [
  { key: "mom", label: "妈妈·孕产档案", icon: HeartPulse },
  { key: "growth", label: "宝宝·生长档案", icon: LineChart },
  { key: "vaccine", label: "宝宝·疫苗计划", icon: Baby },
  { key: "calendar", label: "健康时间轴", icon: Calendar },
];

/** 妈妈记录的阶段徽章（v1.55/1.56：按 exam_items.stage 与孕周判断，含非孕期） */
function MomStageBadge({ record }: { record: HealthRecord }) {
  const stage = record.exam_items?.stage;
  if (stage === "postpartum") {
    return (
      <span className="rounded-full bg-indigo-50 px-2 py-0.5 text-[11px] font-semibold text-indigo-600 dark:bg-indigo-950/50 dark:text-indigo-300">
        产后恢复
      </span>
    );
  }
  if (stage === "general") {
    return (
      <span className="rounded-full bg-sky-50 px-2 py-0.5 text-[11px] font-semibold text-sky-600 dark:bg-sky-950/50 dark:text-sky-300">
        非孕期
      </span>
    );
  }
  if (record.gestational_week) {
    return (
      <span className="rounded-full bg-orange-50 px-2 py-0.5 text-[11px] font-semibold text-brand-600 dark:bg-brand-950/50 dark:text-brand-300">
        孕{record.gestational_week}周
      </span>
    );
  }
  return (
    <span className="rounded-full bg-gray-50 px-2 py-0.5 text-[11px] text-gray-400 dark:bg-gray-800 dark:text-gray-500">
      孕期
    </span>
  );
}

export default function HealthPage() {
  const { hasPermission, user } = useAuthStore();
  const [tab, setTab] = useState<TabKey>("mom");
  const [records, setRecords] = useState<HealthRecord[]>([]);
  const [loading, setLoading] = useState(true);
  const [showCheckIn, setShowCheckIn] = useState(false);
  const [checkInDate, setCheckInDate] = useState<string | undefined>(undefined);
  const [toast, setToast] = useState("");
  const [calendarMonth, setCalendarMonth] = useState(() => new Date());

  const showToast = (msg: string) => {
    setToast(msg);
    setTimeout(() => setToast(""), 2800);
  };

  const load = () => {
    setLoading(true);
    healthApi
      .list()
      .then(setRecords)
      .catch(() => setRecords([]))
      .finally(() => setLoading(false));
  };

  useEffect(() => {
    load();
  }, [tab]);

  /** 打开健康打卡弹窗（可选预填日期，供时间轴补录） */
  const openCheckIn = (date?: string) => {
    setCheckInDate(date || undefined);
    setShowCheckIn(true);
  };

  const remove = async (id: number) => {
    if (!window.confirm("确认删除这条记录？")) return;
    try {
      await healthApi.remove(id);
      showToast("已删除");
      load();
    } catch {
      showToast("删除失败，请重试");
    }
  };

  // ===== v1.55/1.56 统一数据口径：妈妈记录 = prenatal_exam；宝宝记录 = growth_measurement =====
  const momRecords = records.filter((r) => r.record_type === "prenatal_exam");
  const growthRecords = records.filter((r) => r.record_type === "growth_measurement");

  // 生长曲线数据源：仅宝宝测量记录（妈妈数据不再混入宝宝曲线）
  const growthChartPoints = growthRecords.map((r) => ({
    date: r.record_date,
    weight: r.weight,
    height: r.height,
    head: r.head_circumference,
  }));

  return (
    <div className="space-y-5">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-gray-800 dark:text-gray-100">健康中心</h1>
          <p className="mt-1 text-sm text-gray-400">妈妈孕产档案 · 宝宝生长与疫苗 · 全周期时间轴</p>
        </div>
        <button
          className="btn-primary"
          onClick={() => openCheckIn()}
        >
          <Plus className="h-4 w-4" /> 健康打卡
        </button>
      </div>

      {/* Tab 导航 */}
      <div className="flex flex-wrap gap-2">
        {TABS.map((t) => (
          <button
            key={t.key}
            onClick={() => setTab(t.key)}
            className={`flex items-center gap-1.5 rounded-xl px-4 py-2 text-sm transition ${
              tab === t.key
                ? "bg-brand-500 text-white shadow-xs"
                : "border border-gray-100 bg-white text-gray-500 hover:bg-brand-50 dark:border-gray-800 dark:bg-gray-800 dark:text-gray-300 dark:hover:bg-gray-700"
            }`}
          >
            <t.icon className="h-4 w-4" />
            {t.label}
          </button>
        ))}
      </div>

      {/* 统一健康打卡弹窗（唯一录入入口：妈妈孕期/产后/非孕期 + 宝宝生长测量） */}
      <UnifiedHealthCheckIn
        isOpen={showCheckIn}
        onClose={() => setShowCheckIn(false)}
        initialDate={checkInDate}
        onSaved={(archiveHint) => {
          showToast(archiveHint);
          load();
        }}
      />

      {/* Tab 页面主体切换 */}
      {loading ? (
        <p className="py-10 text-center text-gray-400">加载中…</p>
      ) : tab === "mom" ? (
        <div className="space-y-6">
          {/* 妈妈·孕产档案：BMI 分析（状态卡 + 表单 + 时序看板 + 历史表 + 医学评估） */}
          <BmiAnalysisView />

          {/* 打卡明细列表（含备注 / AI 解读 / 阶段徽章） */}
          <div className="space-y-3">
            {momRecords.length === 0 && (
              <div className="card space-y-2 p-8 text-center">
                <HeartPulse className="mx-auto h-8 w-8 text-gray-300 dark:text-gray-600" />
                <p className="text-sm text-gray-400">
                  暂无妈妈记录，点击右上角「健康打卡」记录孕期 / 产后 / 非孕期体重
                </p>
              </div>
            )}
            {momRecords.map((r) => (
              <div key={r.id} className="card flex items-start justify-between">
                <div>
                  <div className="flex items-center gap-2">
                    <CalendarCheck className="h-4 w-4 text-brand-500" />
                    <span className="font-medium text-gray-700 dark:text-gray-200">{r.record_date}</span>
                    <MomStageBadge record={r} />
                    {r.weight != null && (
                      <span className="text-[11px] text-gray-400">体重 {r.weight} kg</span>
                    )}
                  </div>
                  {r.note && (
                    <>
                      <p className="mt-1 text-sm text-gray-500 dark:text-gray-400">{r.note}</p>
                      <div className="mt-1 flex justify-end">
                        <CopyButton text={r.note} label="复制" />
                      </div>
                    </>
                  )}
                  {r.ai_analysis && (
                    <>
                      <p className="mt-2 rounded-lg bg-cream p-2 text-xs text-gray-500 dark:bg-gray-800/80 dark:text-gray-300">
                        AI 解读：{r.ai_analysis}
                      </p>
                      <div className="mt-1 flex justify-end">
                        <CopyButton text={r.ai_analysis} label="复制" />
                      </div>
                    </>
                  )}
                </div>
                {hasPermission("health_record_delete") && (
                  <button className="text-gray-300 hover:text-red-500" onClick={() => remove(r.id)}>
                    <Trash2 className="h-4 w-4" />
                  </button>
                )}
              </div>
            ))}
          </div>
        </div>
      ) : tab === "growth" ? (
        <div className="space-y-5">
          <section className="card space-y-3">
            <div className="flex flex-wrap items-center justify-between gap-2 border-b border-orange-100/60 pb-2 dark:border-gray-800">
              <h2 className="font-semibold text-gray-800 dark:text-gray-100">宝宝生长曲线</h2>
              <span className="text-xs text-gray-400">
                {user?.baby_birthday ? "虚线为 WHO 男童 P50 参考" : "设置宝宝生日后可叠加 WHO 参考线"}
              </span>
            </div>
            <GrowthChart points={growthChartPoints} birthDate={user?.baby_birthday} />
            {growthRecords.length === 0 && (
              <p className="py-4 text-center text-sm text-gray-400">
                暂无宝宝生长数据，点击右上角「健康打卡」选择"宝宝·生长测量"录入
              </p>
            )}
          </section>

          {/* 宝宝测量记录明细表 */}
          {growthRecords.length > 0 && (
            <section className="card">
              <h3 className="mb-2 text-sm font-semibold text-gray-800 dark:text-gray-100">测量记录 ({growthRecords.length})</h3>
              <div className="overflow-x-auto">
                <table className="w-full text-left text-sm">
                  <thead>
                    <tr className="border-b border-gray-100 text-xs text-gray-400 dark:border-gray-800">
                      <th className="px-3 py-2 font-medium">日期</th>
                      <th className="px-3 py-2 font-medium">身高 (cm)</th>
                      <th className="px-3 py-2 font-medium">体重 (kg)</th>
                      <th className="px-3 py-2 font-medium">头围 (cm)</th>
                      <th className="px-3 py-2 font-medium">操作</th>
                    </tr>
                  </thead>
                  <tbody>
                    {[...growthRecords]
                      .sort((a, b) => (a.record_date < b.record_date ? 1 : -1))
                      .map((r) => (
                        <tr key={r.id} className="border-b border-gray-50 transition hover:bg-orange-50/40 dark:border-gray-800/60 dark:hover:bg-gray-800/40">
                          <td className="px-3 py-2 text-gray-700 dark:text-gray-200">{r.record_date}</td>
                          <td className="px-3 py-2 text-gray-600 dark:text-gray-400">{r.height ?? "—"}</td>
                          <td className="px-3 py-2 text-gray-600 dark:text-gray-400">{r.weight ?? "—"}</td>
                          <td className="px-3 py-2 text-gray-600 dark:text-gray-400">{r.head_circumference ?? "—"}</td>
                          <td className="px-3 py-2">
                            {hasPermission("health_record_delete") && (
                              <button className="text-gray-300 hover:text-red-500" onClick={() => remove(r.id)}>
                                <Trash2 className="h-4 w-4" />
                              </button>
                            )}
                          </td>
                        </tr>
                      ))}
                  </tbody>
                </table>
              </div>
            </section>
          )}
        </div>
      ) : tab === "calendar" ? (
        <HealthCalendar
          records={records}
          currentMonth={calendarMonth}
          onMonthChange={setCalendarMonth}
          onDayClick={(_date, dayRecords) => {
            // v1.56 P1-D：点击日期 → 打开健康打卡弹窗并预填该日期（补录入口）
            openCheckIn(_date);
          }}
        />
      ) : (
        <VaccineCalendar records={records} onChanged={load} babyBirthday={user?.baby_birthday} />
      )}

      {toast && (
        <div className="fixed bottom-6 left-1/2 z-50 -translate-x-1/2 rounded-xl bg-gray-900/90 px-4 py-2 text-xs font-medium text-white shadow-lg backdrop-blur">
          {toast}
        </div>
      )}
    </div>
  );
}