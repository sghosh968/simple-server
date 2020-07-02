window.addEventListener("DOMContentLoaded", initializeCharts);

function initializeCharts() {
  const data = getReportingData();
  console.log(data);
  const lineGraphOptions = {
    animation: false,
    responsive: true,
    maintainAspectRatio: false,
    elements: {
      point: {
        pointStyle: "circle",
        backgroundColor: "rgba(81, 205, 130, 1)",
        hoverRadius: 5,
      },
    },
    legend: {
      display: false,
    },
    scales: {
      xAxes: [{
        display: false,
        gridLines: {
          display: false,
          drawBorder: false,
        },
      }],
      yAxes: [{
        display: false,
        gridLines: {
          display: false,
          drawBorder: false,
        },
        ticks: {
          suggestedMin: 0,
          suggestedMax: 60
        }
      }],
    },
    tooltips: {
      caretSize: 6,
      position: "average",
      yAlign: "bottom",
      xAlign: "center",
      titleFontFamily: "Roboto Condensed",
      bodyFontFamily: "Roboto Condensed",
      backgroundColor: "rgb(0, 0, 0)",
      titleFontSize: 16,
      bodyFontSize: 14,
      titleAlign: "center",
      bodyAlign: "center",
      displayColors: false,
      yPadding: 12,
      xPadding: 12,
      callbacks: {
        title: function() {},
        label: function(tooltipItem, _) {
          const controlledPatientDate = data.controlledPatients.map(key => key[0])[tooltipItem.index];
          const controlledPatientValue = data.controlledPatients.map(key => key[1])[tooltipItem.index];
          const formattedValue = controlledPatientValue.toString().replace(/\B(?=(\d{3})+(?!\d))/g, ",");
          let value = parseInt(tooltipItem.value).toFixed(0);
          return `${value}% control rate (${formattedValue} patients) in ${controlledPatientDate}`;
        },
      },
    }
  };

  const graphConfig = {
    type: "line",
    data: {
      labels: data.controlRate.map(key => key[0]),
      datasets: [{
        backgroundColor: "rgba(242, 248, 245, 1)",
        borderColor: "rgba(0, 122, 49, 1)",
        borderWidth: 1,
        pointBackgroundColor: "rgba(0, 122, 49, 1)",
        data: data.controlRate.map(key => key[1]),
      }],
    },
    options: lineGraphOptions 
  };

  var graphCanvas =
    document.getElementById("controlledPatientsTrend").getContext("2d");

  new Chart(graphCanvas, graphConfig);

};

function getReportingData() {
  const $reportingDiv = document.getElementById("reporting");
  const controlledPatients = 
    JSON.parse($reportingDiv.attributes.getNamedItem("data-controlled-patients").value);
  const registrations =
    JSON.parse($reportingDiv.attributes.getNamedItem("data-registrations").value);
  const quarterlyRegistrations =
    JSON.parse($reportingDiv.attributes.getNamedItem("data-quarterly-registrations").value);
  
  let data = {
    controlledPatients: Object.entries(controlledPatients),
    registrations: Object.entries(registrations),
  };

  let controlRate = computeControlRate(data.controlledPatients, data.registrations);
  data.controlRate = controlRate;

  return data;
};

function computeControlRate(controlledPatients, registrations) {
  return controlledPatients.map(function(key, index) {
    const registrationData = registrations[index];
    const controlRate = numberToPercent(key[1], registrationData[1]);

    return [key[0], controlRate];
  });
};

function numberToPercent(numerator, denominator) {
  return parseFloat(((numerator/denominator)*100).toFixed(0));
};